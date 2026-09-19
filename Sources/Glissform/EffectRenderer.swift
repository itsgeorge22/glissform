import AppKit
import CoreVideo
import MetalKit

/// Draws an opaque, angle-driven desktop transition. All public instance calls use the main queue.
final class EffectRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var sourceTexture: CVMetalTexture?
    private var sourceBuffer: CVPixelBuffer?
    private var filteredTexture: MTLTexture?
    private var sourceNeedsFiltering = true
    private var foldRadians: Float = 0
    private var fullClosureRadians: Float = 1
    private var smoothing = MotionSmoothing()
    private var lastDrawTime: TimeInterval?
    private var handoff = HandoffTransition()
    private var renderedFold: Float = 0
    private var ending = false
    private var transitionGeneration = 0
    private var onReturnToFlat: (() -> Void)?

    func beginAnimation() {
        transitionGeneration += 1
        ending = false
        onReturnToFlat = nil
        handoff.begin(from: renderedFold)
        smoothing.reset(to: foldRadians)
        scheduleSettling()
    }

    func finishAnimation(completion: @escaping () -> Void) {
        transitionGeneration += 1
        ending = true
        onReturnToFlat = completion
        handoff.begin(from: renderedFold)
        scheduleSettling()
    }

    private func scheduleSettling() {
        guard progress > 0, sourceBuffer != nil, let view else { return }
        if view.isPaused { lastDrawTime = ProcessInfo.processInfo.systemUptime }
        view.isPaused = false
    }
    private var blurScale: Float = 1 // Set to zero only for geometric GPU validation.

    /// The reference desktop is a fixed plane at the angle where closure starts.
    /// Camera distance/height are in screen-height units, for a normal seated view.
    func setLidAngle(_ angle: Double, referenceAngle: Double) {
        guard angle.isFinite, referenceAngle.isFinite else { return }
        fullClosureRadians = ScreenProjection.foldRadians(lidAngle: 4, referenceAngle: referenceAngle)
        let next = ScreenProjection.foldRadians(lidAngle: angle, referenceAngle: referenceAngle)
        guard next != foldRadians else { return }
        foldRadians = next
        scheduleSettling()
    }

    var progress: Float = 0 {
        didSet {
            progress = progress.isFinite ? min(max(progress, 0), 1) : 0
            guard progress != oldValue else { return }
            if progress == 0 {
                view?.isPaused = true
                lastDrawTime = nil
                smoothing.reset()
            } else { scheduleSettling() }
        }
    }

    init?(view: MTKView, framesPerSecond: Int = 60) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "hingeFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Glissform renderer initialization failed: %@", String(describing: error))
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.view = view
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            return nil
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.isPaused = true
        view.preferredFramesPerSecond = max(60, framesPerSecond)
        // Event-driven drawing disables MetalKit's frame loop, even when we
        // unpause it. Timed drawing lets the 60 ms settle fill sensor intervals.
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.delegate = self
    }

    func update(pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let cache = textureCache else { return }
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &texture
        )
        guard result == kCVReturnSuccess, let texture else { return }
        sourceTexture = texture
        sourceBuffer = pixelBuffer
        sourceNeedsFiltering = true
        scheduleSettling()
    }

    /// Submit a sharp identity frame while the overlay is still transparent.
    /// The caller may reveal the window only after the GPU has finished it.
    @MainActor func prepareSnapshot(pixelBuffer: CVPixelBuffer) async throws {
        progress = 0
        update(pixelBuffer: pixelBuffer)
        guard sourceTexture != nil, let view,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let command = encode(descriptor: descriptor, displayedFold: 0) else {
            throw NSError(domain: "Glissform", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot prepare the first animation frame"])
        }
        command.present(drawable)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            command.addCompletedHandler { completed in
                if let error = completed.error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
            command.commit()
        }
    }

    func clear() {
        view?.isPaused = true
        lastDrawTime = nil
        smoothing.reset()
        renderedFold = 0
        handoff = HandoffTransition()
        ending = false
        transitionGeneration += 1
        onReturnToFlat = nil
        sourceTexture = nil
        sourceBuffer = nil
        filteredTexture = nil
        sourceNeedsFiltering = true
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - (lastDrawTime ?? now)
        lastDrawTime = now
        let followingFold = ending ? 0 : smoothing.step(toward: foldRadians, elapsed: elapsed)
        let displayedFold = handoff.step(toward: followingFold, elapsed: elapsed)
        renderedFold = displayedFold
        let settled = (!handoff.active && (ending || displayedFold == foldRadians)) || progress == 0
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = encode(descriptor: descriptor, displayedFold: displayedFold) else { return }
        if ending, !handoff.active, let completion = onReturnToFlat {
            onReturnToFlat = nil
            let token = transitionGeneration
            commandBuffer.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.transitionGeneration == token else { return }
                    completion()
                }
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // Retry a temporarily unavailable drawable rather than losing the last
        // flat frame and its cleanup callback.
        if settled { view.isPaused = true }
    }

    private func encode(descriptor: MTLRenderPassDescriptor, displayedFold: Float? = nil) -> MTLCommandBuffer? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        // Retain both wrappers until the GPU has finished reading the IOSurface.
        let retainedTexture = sourceTexture
        let retainedBuffer = sourceBuffer
        var sampledTexture: MTLTexture?
        if let retainedTexture, let texture = CVMetalTextureGetTexture(retainedTexture) {
            if filteredTexture?.width != texture.width || filteredTexture?.height != texture.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                    width: texture.width, height: texture.height, mipmapped: true)
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead]
                filteredTexture = device.makeTexture(descriptor: descriptor)
                sourceNeedsFiltering = true
            }
            if sourceNeedsFiltering, let filteredTexture, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                          sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                          to: filteredTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
                blit.generateMipmaps(for: filteredTexture)
                blit.endEncoding()
                sourceNeedsFiltering = false
            }
            sampledTexture = filteredTexture ?? texture
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
        if let texture = sampledTexture {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            let visibleAngle = displayedFold ?? foldRadians
            let fraction = min(1, max(0, visibleAngle / max(0.001, fullClosureRadians)))
            let visibleProgress = fraction * fraction * (3 - 2 * fraction)
            var uniforms = SIMD4<Float>(visibleProgress, Float(texture.width), Float(texture.height), visibleAngle)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            var frost = blurScale
            encoder.setFragmentBytes(&frost, length: MemoryLayout<Float>.stride, index: 1)
            var eye = SIMD2<Float>(ScreenProjection.eyeDistance, ScreenProjection.eyeHeight)
            encoder.setFragmentBytes(&eye, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(retainedTexture) {}
            withExtendedLifetime(retainedBuffer) {}
        }
        return commandBuffer
    }

    /// Renders synthetic pixels only; does not request permission or read the user's screen.
    /// Writes outputURL at 65% progress and a sibling *.clear.png at zero progress.
    static func selfTest(outputURL: URL, benchmark: Bool = false) throws {
        func failure(_ message: String) -> NSError {
            NSError(domain: "Glissform.RendererTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let width = benchmark ? 2880 : 960, height = benchmark ? 1864 : 600
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        guard let renderer = EffectRenderer(view: view) else { throw failure("Metal initialization failed") }
        guard !view.enableSetNeedsDisplay, view.preferredFramesPerSecond == 60 else {
            throw failure("Smoothing requires MetalKit's timed frame loop")
        }
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                 attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw failure("Cannot allocate synthetic pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw failure("No pixel storage") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                let grid = (x % 80 < 3 || y % 60 < 3)
                bytes[offset] = grid ? 245 : UInt8(35 + y * 180 / height)
                bytes[offset + 1] = grid ? 245 : UInt8(35 + x * 180 / width)
                bytes[offset + 2] = grid ? 245 : UInt8(220 - y * 160 / height)
                bytes[offset + 3] = 255
            }
        }
        let originalPixels = Array(UnsafeBufferPointer(start: bytes, count: rowBytes * height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        renderer.update(pixelBuffer: buffer)
        guard renderer.sourceTexture != nil else { throw failure("CVMetalTexture conversion failed") }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The sharp intermediate frames test the actual shader independently of
        // the frosting. They must match rays through a rotating physical panel.
        let cases: [(Float, Float, Double, String)] = [(0, 1, 85, "clear"), (0.5, 1, 85, "zeroAngle"),
            (0.2, 0, 85, "projection16"), (0.5, 0, 85, "projection40"),
            (1.125, 0, 100, "projection90"), (1.5, 0, 130, "projection120"),
            (0.25, 1, 85, "frost20"), (0.5, 1, 85, "frost40"), (0.65, 1, 85, "frost52"),
            (1, 1, 85, "frost80"), (1.0125, 1, 85, "fullShadow")]
        var sharpBottomEdgeEnergy: Double?
        for (amount, frost, reference, label) in cases {
            renderer.progress = amount
            renderer.blurScale = frost
            renderer.setLidAngle(label == "zeroAngle" ? reference : reference - Double(amount) * 80,
                                 referenceAngle: reference)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let destination = renderer.device.makeTexture(descriptor: descriptor) else { throw failure("Cannot create render target") }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = destination
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            guard let command = renderer.encode(descriptor: pass) else { throw failure("Cannot encode render") }
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            var rendered = [UInt8](repeating: 0, count: width * height * 4)
            rendered.withUnsafeMutableBytes {
                destination.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            if label == "projection40" || label == "frost40" {
                // Compare identical projection/shadow with and without frost.
                // Thin synthetic grid edges at the hinge must actually soften;
                // a gap-only blur leaves this band almost completely sharp.
                var energy = 0.0
                for y in (height - 12)..<(height - 2) {
                    for x in (width / 10)..<(width * 9 / 10) {
                        let offset = (y * width + x) * 4
                        let difference = Double(rendered[offset]) - Double(rendered[offset - 4])
                        energy += difference * difference
                    }
                }
                if label == "projection40" { sharpBottomEdgeEnergy = energy }
                else {
                    guard let sharpBottomEdgeEnergy, sharpBottomEdgeEnergy > 0,
                          energy < sharpBottomEdgeEnergy * 0.65 else {
                        throw failure("Progressive frost must soften the bottom edge as well as the top")
                    }
                }
            }
            if amount == 0 || label == "zeroAngle" {
                // Asymmetric markers catch both vertical inversion and horizontal mirroring.
                for (x, y) in [(17, 19), (911, 23), (29, 563), (901, 557)] {
                    let offset = (y * width + x) * 4
                    let expected = [35 + y * 180 / height, 35 + x * 180 / width, 220 - y * 160 / height, 255]
                    guard (0..<4).allSatisfy({ abs(Int(rendered[offset + $0]) - expected[$0]) <= 1 }) else {
                        throw failure("Zero-progress pixel mismatch at \(x),\(y)")
                    }
                }
            }
            if frost == 0 {
                let theta = Double(amount) * 80 * .pi / 180
                for (x, y) in [(17, 19), (911, 23), (29, 563), (901, 557), (340, 230), (620, 390)] {
                    // Independent ray/plane intersection in screen-height units.
                    let surface = SIMD3<Double>((Double(x) + 0.5) / Double(width) - 0.5,
                                                (1 - (Double(y) + 0.5) / Double(height)) * cos(theta),
                                                (1 - (Double(y) + 0.5) / Double(height)) * sin(theta))
                    let eye = SIMD3<Double>(0, 1.10, 4.0)
                    let direction = surface - eye
                    let pointOnReference = eye + direction * (-eye.z / direction.z)
                    let sx = (pointOnReference.x + 0.5) * Double(width) - 0.5
                    let sy = (1 - pointOnReference.y) * Double(height) - 0.5
                    let ix = Int(floor(sx)), iy = Int(floor(sy))
                    let fx = sx - Double(ix), fy = sy - Double(iy)
                    for channel in 0..<3 {
                        var expected = 0.0
                        for dy in 0...1 { for dx in 0...1 {
                            let px = ix + dx, py = iy + dy
                            if (0..<width).contains(px), (0..<height).contains(py) {
                                let weight = (dx == 0 ? 1 - fx : fx) * (dy == 0 ? 1 - fy : fy)
                                expected += Double(originalPixels[py * rowBytes + px * 4 + channel]) * weight
                            }
                        } }
                        let heightFromHinge = 1 - (Double(y) + 0.5) / Double(height)
                        func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
                            let t = min(1, max(0, (value - low) / (high - low)))
                            return t * t * (3 - 2 * t)
                        }
                        let rawProgress = min(1, Double(amount) * 80 / (reference - 4))
                        let visibleProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                        let darkness = pow(visibleProgress, 2.2)
                            * (1 - smoothstep(0.05, 1, 1 - heightFromHinge))
                        expected *= 1 - darkness
                        guard abs(Double(rendered[(y * width + x) * 4 + channel]) - expected) < 2 else {
                            throw failure("Stationary-image projection mismatch at \(label), \(x),\(y), channel \(channel)")
                        }
                    }
                }
            }
            if label == "fullShadow" {
                for y in 0..<Int(Double(height) * 0.05) {
                    for x in 0..<width {
                        let offset = (y * width + x) * 4
                        guard rendered[offset] == 0, rendered[offset + 1] == 0, rendered[offset + 2] == 0 else {
                            throw failure("Top 5 percent must be pitch black at \(label), \(x),\(y)")
                        }
                    }
                }
            }
            guard stride(from: 3, to: rendered.count, by: 4).allSatisfy({ rendered[$0] == 255 }) else {
                throw failure("Output must be opaque")
            }
            let data = Data(rendered)
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw failure("PNG encoding failed")
            }
            let target = label == "frost52" ? outputURL : outputURL.deletingPathExtension().appendingPathExtension("\(label).png")
            try png.write(to: target)
        }
        print("PASS: stationary-plane GPU projection at 16°/40°/90°/120°, orientation, opacity, top shadow, bottom-edge blur, frost at 20°/40°/52°/80°")
        if benchmark {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget]
            guard let destination = renderer.device.makeTexture(descriptor: descriptor) else {
                throw failure("Cannot allocate benchmark target")
            }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = destination
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            var milliseconds: [Double] = []
            for frame in 0..<130 {
                // Warm up 10 frames, then sweep through closing and reopening.
                let phase = Double(max(0, frame - 10)) / 119 * .pi
                let fold = Float(sin(phase) * 95 * .pi / 180)
                guard let command = renderer.encode(descriptor: pass, displayedFold: fold) else {
                    throw failure("Cannot encode benchmark frame")
                }
                command.commit()
                command.waitUntilCompleted()
                if let error = command.error { throw error }
                if frame >= 10 {
                    milliseconds.append((command.gpuEndTime - command.gpuStartTime) * 1000)
                }
            }
            milliseconds.sort()
            print(String(format: "GPU-only synthetic %dx%d, 120 frames: mean %.2f ms, p95 %.2f ms, max %.2f ms (excludes capture, compositor and display pacing)",
                         width, height, milliseconds.reduce(0, +) / Double(milliseconds.count),
                         milliseconds[Int(Double(milliseconds.count - 1) * 0.95)], milliseconds.last!))
        }
        renderer.clear()
        guard view.isPaused else { throw failure("Clearing must stop the frame loop") }
    }

    /// Original synthetic desktop artwork for material review, never a screen capture.
    static func materialPreview(outputDirectory: URL) throws {
        let width = 960, height = 600
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        guard let renderer = EffectRenderer(view: view) else {
            throw NSError(domain: "Glissform.MaterialPreview", code: 1)
        }
        var storage: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                         kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &storage)
        guard let buffer = storage else { throw NSError(domain: "Glissform.MaterialPreview", code: 2) }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            throw NSError(domain: "Glissform.MaterialPreview", code: 3)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        func card(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 18) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .white,
                   weight: NSFont.Weight = .regular) {
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.15, blue: 0.37, alpha: 1),
                            NSColor(srgbRed: 0.55, green: 0.35, blue: 0.58, alpha: 1),
                            NSColor(srgbRed: 0.91, green: 0.66, blue: 0.43, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 35)
        NSColor(srgbRed: 0.22, green: 0.34, blue: 0.57, alpha: 1).setFill()
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: 0, y: 0)); hill.line(to: NSPoint(x: 0, y: 230))
        hill.curve(to: NSPoint(x: 960, y: 185), controlPoint1: NSPoint(x: 380, y: 450), controlPoint2: NSPoint(x: 540, y: 35))
        hill.line(to: NSPoint(x: 960, y: 0)); hill.close(); hill.fill()
        card(NSRect(x: 0, y: 574, width: 960, height: 26), NSColor.black.withAlphaComponent(0.2), radius: 0)
        label("Studio    File    Edit    View", x: 22, y: 580, size: 12, weight: .semibold)
        label("Monday   9:41", x: 842, y: 580, size: 12)
        card(NSRect(x: 40, y: 359, width: 240, height: 174), NSColor(srgbRed: 0.90, green: 0.94, blue: 0.99, alpha: 1))
        label("MONDAY", x: 60, y: 496, size: 13, color: .systemRed, weight: .semibold)
        label("19", x: 57, y: 423, size: 64, color: .darkGray, weight: .light)
        label("A little space to think.", x: 60, y: 384, size: 16, color: .darkGray)
        card(NSRect(x: 40, y: 190, width: 240, height: 143), NSColor(srgbRed: 0.17, green: 0.54, blue: 0.86, alpha: 1))
        label("Clear skies", x: 60, y: 297, size: 15, weight: .medium)
        label("21°", x: 57, y: 233, size: 52, weight: .light)
        label("A bright afternoon ahead", x: 60, y: 211, size: 13)
        card(NSRect(x: 325, y: 156, width: 590, height: 377), NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1), radius: 12)
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            card(NSRect(x: 344 + index * 20, y: 505, width: 12, height: 12), color, radius: 6)
        }
        label("Studio", x: 430, y: 503, size: 14, color: .darkGray, weight: .semibold)
        label("Make room for ideas.", x: 360, y: 443, size: 30, color: .darkGray, weight: .semibold)
        label("Notes, sketches and small discoveries.", x: 360, y: 412, size: 16, color: .gray)
        for (index, color) in [NSColor.systemOrange, .systemPurple, .systemTeal].enumerated() {
            let x = 360 + index * 172
            card(NSRect(x: x, y: 245, width: 148, height: 140), color.withAlphaComponent(0.22), radius: 10)
            card(NSRect(x: x + 16, y: 306, width: 49, height: 49), color, radius: 12)
            label(["Explore", "Create", "Collect"][index], x: CGFloat(x + 16), y: 272,
                  size: 16, color: .darkGray, weight: .semibold)
        }
        label("Everything starts with a little curiosity.", x: 360, y: 196, size: 15, color: .gray)
        card(NSRect(x: 213, y: 25, width: 534, height: 80), NSColor.white.withAlphaComponent(0.32), radius: 22)
        let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .darkGray]
        let symbols = ["folder.fill", "message.fill", "calendar", "music.note", "photo", "safari", "gearshape.fill"]
        for index in 0..<7 {
            let x = 229 + index * 73
            card(NSRect(x: x, y: 38, width: 64, height: 54), colors[index], radius: 13)
            if let icon = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil) {
                icon.draw(in: NSRect(x: x + 15, y: 49, width: 34, height: 32))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        renderer.update(pixelBuffer: buffer)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        guard let target = renderer.device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "Glissform.MaterialPreview", code: 4)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        for degrees in [0, 12, 24, 40, 60] {
            renderer.setLidAngle(95 - Double(degrees), referenceAngle: 95)
            guard let command = renderer.encode(descriptor: pass) else {
                throw NSError(domain: "Glissform.MaterialPreview", code: 5)
            }
            command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: outputDirectory.appendingPathComponent("fold-\(degrees).png"))
        }
        renderer.clear()
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 uv; };
    vertex Vertex fullscreenVertex(uint id [[vertex_id]]) {
        const float2 positions[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
        float2 p = positions[id];
        return {float4(p, 0, 1), float2((p.x + 1) * 0.5, (1 - p.y) * 0.5)};
    }
    fragment float4 hingeFragment(Vertex in [[stage_in]], texture2d<float> desktop [[texture(0)]],
                                   constant float4 &uniforms [[buffer(0)]], constant float &frost [[buffer(1)]],
                                   constant float2 &eye [[buffer(2)]]) {
        constexpr sampler sampling(coord::normalized, address::clamp_to_zero, filter::linear, mip_filter::linear);
        float theta = max(0.0f, uniforms.w);
        // Only the displayed angle controls effect strength; a raw sensor
        // threshold must never switch the shader on or off during a handoff.
        if (theta == 0.0f) return float4(desktop.sample(sampling, in.uv, level(0)).rgb, 1);
        float heightFromHinge = 1.0f - in.uv.y;
        // Rotate each physical display pixel towards a fixed viewer, then trace
        // its viewing ray back to the ORIGINAL upright image plane (z = 0).
        // This is a projective window into stationary content, not a UV zoom.
        // At the hinge z=0 so source and screen coincide at every lid angle.
        float eyeDistance = eye.x;
        float eyeHeight = eye.y;
        float depth = heightFromHinge * sin(theta);
        float planeHeight = heightFromHinge * cos(theta);
        float rayScale = eyeDistance / (eyeDistance - depth);
        float2 uv = float2(0.5f + (in.uv.x - 0.5f) * rayScale,
                          1.0f - (eyeHeight + (planeHeight - eyeHeight) * rayScale));
        // Closing progressively diffuses the whole stretched image, including
        // the hinge. Add more diffusion toward the top, furthest from the plane.
        // Use displayed closure progress rather than sin(theta): blur must keep
        // increasing even when a gesture rotates past 90 degrees, and reverse
        // continuously on reopening. The prepared zero-angle frame stays sharp.
        float verticalBlur = smoothstep(0.0f, 1.0f, heightFromHinge);
        // Diffusion establishes the frosted material early, then keeps growing
        // gently. Large colored shapes survive after text and icon detail merge.
        float frostAmount = (1.0f - exp(-3.0f * uniforms.x)) / (1.0f - exp(-3.0f));
        float radius = frostAmount * uniforms.z * mix(0.015f, 0.090f, verticalBlur) * frost;
        float2 pixel = 1.0f / max(uniforms.yz, float2(1));
        float2 step = pixel * radius * 0.5f;
        // A normalized Gaussian-like kernel over prefiltered mip levels gives
        // broad, continuous diffusion without the old concentric sample rings.
        // Mip interpolation keeps changes in blur strength continuous in motion.
        const float weights[] = {0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f};
        // The lower mip footprint must cover at least the half-radius spacing
        // between taps. Smaller footprints leave gaps and repeat glyph edges.
        float lod = log2(max(1.0f, radius));
        float3 color = float3(0);
        for (uint y = 0; y < 5; ++y) {
            for (uint x = 0; x < 5; ++x) {
                float2 offset = float2(float(x) - 2.0f, float(y) - 2.0f) * step;
                color += desktop.sample(sampling, uv + offset, level(lod)).rgb * weights[x] * weights[y];
            }
        }
        // The top recedes into shadow; the hinge stays lit. Use the displayed
        // angle so shadow, projection and frost share the same soft stop.
        // Build throughout the whole animation. The gradient extends from
        // transparent at the bottom to a black plateau across the top 5%.
        // Keep blurred colors luminous until the deep shadow builds near closure.
        float darkness = pow(uniforms.x, 2.2f)
                         * (1.0f - smoothstep(0.05f, 1.0f, in.uv.y));
        return float4(color * (1.0f - darkness), 1);
    }
    """
}
