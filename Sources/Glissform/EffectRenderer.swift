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
        fullClosureRadians = Float(max(1, referenceAngle - 4) * 0.867 * .pi / 180)
        let next = Float(min(89, max(0, referenceAngle - angle)) * 0.867 * .pi / 180)
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

    init?(view: MTKView) {
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
        view.preferredFramesPerSecond = 60
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
            let fraction = min(1, max(0, visibleAngle / fullClosureRadians))
            let visibleProgress = fraction * fraction * (3 - 2 * fraction)
            var uniforms = SIMD4<Float>(visibleProgress, Float(texture.width), Float(texture.height), visibleAngle)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            var frost = blurScale
            encoder.setFragmentBytes(&frost, length: MemoryLayout<Float>.stride, index: 1)
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
    static func selfTest(outputURL: URL) throws {
        func failure(_ message: String) -> NSError {
            NSError(domain: "Glissform.RendererTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let width = 960, height = 600
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
        let cases: [(Float, Float, String)] = [(0, 1, "clear"), (0.5, 1, "zeroAngle"), (0.2, 0, "projection16"),
                                             (0.5, 0, "projection40"), (0.25, 1, "frost20"),
                                             (0.65, 1, "frost52"), (1, 1, "frost80"), (1.0125, 1, "fullShadow")]
        for (amount, frost, label) in cases {
            renderer.progress = amount
            renderer.blurScale = frost
            renderer.setLidAngle(label == "zeroAngle" ? 85 : 85 - Double(amount) * 80, referenceAngle: 85)
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
                let theta = Double(amount) * 80 * 0.867 * .pi / 180
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
                        let rawProgress = Double(amount) * 80 / 81
                        let visibleProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                        let darkness = smoothstep(0, 1, visibleProgress)
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
        print("PASS: stationary-plane GPU projection at 16° and 40°, orientation, opacity, top shadow, frost at 20°/52°/80°")
        renderer.clear()
        guard view.isPaused else { throw failure("Clearing must stop the frame loop") }
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
                                   constant float4 &uniforms [[buffer(0)]], constant float &frost [[buffer(1)]]) {
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
        const float eyeDistance = 4.0f;
        const float eyeHeight = 1.10f;
        float depth = heightFromHinge * sin(theta);
        float planeHeight = heightFromHinge * cos(theta);
        float rayScale = eyeDistance / (eyeDistance - depth);
        float2 uv = float2(0.5f + (in.uv.x - 0.5f) * rayScale,
                          1.0f - (eyeHeight + (planeHeight - eyeHeight) * rayScale));
        // Frost comes from the physical gap to that plane: sharp near the hinge,
        // diffuse where the moving surface is furthest away. No global dim/zoom.
        float radius = depth * uniforms.z * 0.0495f * frost;
        float2 pixel = 1.0f / max(uniforms.yz, float2(1));
        float2 step = pixel * radius;
        // Prefiltered mip levels avoid sparse-tap ghosting on text and thin edges.
        float lod = log2(max(1.0f, radius * 0.55f));
        float3 color = desktop.sample(sampling, uv, level(lod)).rgb * 0.20f;
        for (uint i = 0; i < 8; ++i) {
            float angle = float(i) * 0.78539816339f;
            float2 offset = float2(cos(angle), sin(angle));
            color += desktop.sample(sampling, uv + offset * step * 0.46f, level(lod)).rgb * 0.065f;
            color += desktop.sample(sampling, uv + offset * step, level(lod)).rgb * 0.035f;
        }
        // The top recedes into shadow; the hinge stays lit. Use the displayed
        // angle so shadow, projection and frost share the same soft stop.
        // Build throughout the whole animation. The gradient extends from
        // transparent at the bottom to a black plateau across the top 5%.
        float darkness = smoothstep(0.0f, 1.0f, uniforms.x)
                         * (1.0f - smoothstep(0.05f, 1.0f, in.uv.y));
        return float4(color * (1.0f - darkness), 1);
    }
    """
}
