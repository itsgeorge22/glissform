import AppKit
import CoreVideo
import MetalKit
import QuartzCore
import OSLog
import MetalPerformanceShaders

/// Draws an opaque, angle-driven desktop transition. All public instance calls use the main queue.
final class EffectRenderer: NSObject, MTKViewDelegate, CAMetalDisplayLinkDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let gaussianPyramid: MPSImageGaussianPyramid
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
    private var displayLink: CAMetalDisplayLink?
    private var frameRate: Float = 60
    private var syntheticTarget: MTLTexture?
    private let allowsSyntheticFrames = CommandLine.arguments.contains("--lifecycle-test")
    private var sampleTime: Double = 0
    private var renderedVelocity: Double = 0
    private(set) var opacity: Float = 1
    private var fadeOrigin: Float = 1
    private var fadeTarget: Float = 1
    private var fadeElapsed: Double = 0
    private var fadeDuration: Double = 0
    private var fadingOut = false
    private let timingLog = Logger(subsystem: "com.george.glissform.mvp", category: "AnimationTiming")
    private let timingEnabled = ProcessInfo.processInfo.environment["GLISSFORM_MOTION_DIAGNOSTICS"] == "1"
    private var firstPresentationPending = true
    private var previousPresentation: Double = 0
    private(set) var renderedFrameCount = 0

    var isRendering: Bool { displayLink?.isPaused == false }

    var hasPreparedSnapshot: Bool {
        sourceBuffer != nil && sourceTexture != nil && filteredTexture != nil && !sourceNeedsFiltering
    }

    func beginAnimation(opening: Bool = false) {
        let interruptedReturn = ending
        transitionGeneration += 1
        ending = false
        fadingOut = false
        onReturnToFlat = nil
        if !opening || interruptedReturn {
            handoff.begin(from: renderedFold, velocity: renderedVelocity, holdFirstFrame: false)
        }
        fade(to: 1, duration: opening ? 0.050 : (opacity < 1 ? 0.040 : 0))
        scheduleSettling()
    }

    func finishAnimation(restoringPause: Bool = false, completion: @escaping () -> Void) {
        transitionGeneration += 1
        ending = true
        onReturnToFlat = completion
        fadingOut = false
        let distance = Double(abs(renderedFold))
        let duration = restoringPause ? min(0.300, max(0.100, distance * 0.35))
            : min(0.180, max(0.060, distance / max(0.5, abs(renderedVelocity))))
        handoff.begin(from: renderedFold, velocity: renderedVelocity, duration: duration, holdFirstFrame: false)
        fadeDuration = 0
        scheduleSettling()
    }

    private func fade(to target: Float, duration: Double) {
        fadeOrigin = opacity
        fadeTarget = target
        fadeElapsed = 0
        fadeDuration = duration
        if duration == 0 { opacity = target }
    }

    private func scheduleSettling() {
        guard progress > 0, sourceBuffer != nil else { return }
        if !isRendering { lastDrawTime = ProcessInfo.processInfo.systemUptime }
        ensureDisplayLink()
        displayLink?.isPaused = false
    }
    private var blurScale: Float = 1 // Set to zero only for geometric GPU validation.
    private var ditherScale: Float = 1 // Disable only for the dark-gradient comparison.

    /// The reference desktop is a fixed plane at the angle where closure starts.
    /// Camera distance/height are in screen-height units, for a normal seated view.
    func setLidAngle(_ angle: Double, referenceAngle: Double,
                     sampleTime: Double = ProcessInfo.processInfo.systemUptime) {
        guard angle.isFinite, referenceAngle.isFinite else { return }
        self.sampleTime = sampleTime
        fullClosureRadians = ScreenProjection.foldRadians(lidAngle: 4, referenceAngle: referenceAngle)
        let next = ScreenProjection.foldRadians(lidAngle: angle, referenceAngle: referenceAngle)
        smoothing.ingest(target: next, at: sampleTime)
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
                displayLink?.isPaused = true
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
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Glissform renderer initialization failed: %@", String(describing: error))
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.gaussianPyramid = MPSImageGaussianPyramid(device: device)
        self.gaussianPyramid.edgeMode = .zero
        self.view = view
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            return nil
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.isPaused = true
        view.preferredFramesPerSecond = max(60, framesPerSecond)
        // CAMetalDisplayLink owns production draws; MetalKit remains paused.
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.delegate = self
        view.layer?.isOpaque = false
        guard view.layer is CAMetalLayer else { return nil }
        frameRate = Float(max(1, framesPerSecond))
        // Compile the pyramid's kernels before a gesture needs its first frame.
        // Only synthetic pixels are involved, and the queue preserves ordering.
        let warmupDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 64, height: 64, mipmapped: true)
        warmupDescriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        warmupDescriptor.storageMode = .shared
        if var texture = device.makeTexture(descriptor: warmupDescriptor),
           let command = queue.makeCommandBuffer() {
            let zeroes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            texture.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0,
                            withBytes: zeroes, bytesPerRow: 64 * 4)
            gaussianPyramid.encode(commandBuffer: command, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
            command.commit()
        }
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

    /// Prepare the identity frame for closing, or the current fold for waking.
    /// The caller may reveal the window only after the GPU has finished it.
    @MainActor func prepareSnapshot(pixelBuffer: CVPixelBuffer, opening: Bool = false) async throws {
        progress = 0
        update(pixelBuffer: pixelBuffer)
        try await prepareFirstFrame(opening: opening)
    }

    /// Reuse the closing image and its mipmaps, without a capture or texture upload.
    @MainActor func prepareRetainedSnapshot() async throws {
        guard hasPreparedSnapshot else {
            throw NSError(domain: "Glissform", code: 5, userInfo: [NSLocalizedDescriptionKey: "Closing screenshot unavailable"])
        }
        progress = 0
        try await prepareFirstFrame(opening: true)
    }

    @MainActor private func prepareFirstFrame(opening: Bool) async throws {
        // A display link owns drawable acquisition even while paused. Detach it
        // before preparing the hidden first frame; resume ownership at reveal.
        displayLink?.invalidate()
        displayLink = nil
        let initialFold: Float = opening ? foldRadians : 0
        opacity = opening ? 0 : 1
        fadeDuration = 0
        firstPresentationPending = true
        previousPresentation = 0
        renderedFold = initialFold
        renderedVelocity = 0
        smoothing.reset(to: foldRadians, at: sampleTime)
        if opening {
            renderedFold = initialFold
            smoothing.reset(to: initialFold, at: sampleTime)
            handoff = HandoffTransition()
        }
        guard sourceTexture != nil, let layer = view?.layer as? CAMetalLayer,
              let drawable = layer.nextDrawable() else {
            throw NSError(domain: "Glissform", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot prepare the first animation frame"])
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let command = encode(descriptor: descriptor, displayedFold: initialFold, opacity: opacity) else {
            throw NSError(domain: "Glissform", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot encode the first animation frame"])
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

    /// Stop drawing and invalidate callbacks, while keeping the single image ready.
    func pauseSnapshot() {
        progress = 0
        view?.isPaused = true
        displayLink?.isPaused = true
        lastDrawTime = nil
        smoothing.reset()
        renderedFold = 0
        renderedVelocity = 0
        opacity = 1
        fadeDuration = 0
        fadingOut = false
        handoff = HandoffTransition()
        ending = false
        transitionGeneration += 1
        onReturnToFlat = nil
    }

    func clear() {
        pauseSnapshot()
        sourceTexture = nil
        sourceBuffer = nil
        filteredTexture = nil
        syntheticTarget = nil
        sourceNeedsFiltering = true
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func ensureDisplayLink() {
        guard displayLink == nil, let layer = view?.layer as? CAMetalLayer else { return }
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        link.preferredFrameLatency = 1
        link.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit { displayLink?.invalidate() }

    /// Synthetic lifecycle checks can explicitly pump a frame while occluded.
    func draw(in view: MTKView) {
        guard allowsSyntheticFrames, progress > 0 else { return }
        let width = max(1, Int(view.drawableSize.width)), height = max(1, Int(view.drawableSize.height))
        if syntheticTarget?.width != width || syntheticTarget?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat,
                                                                      width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            syntheticTarget = device.makeTexture(descriptor: descriptor)
        }
        guard let target = syntheticTarget else { return }
        render(to: target, at: ProcessInfo.processInfo.systemUptime)
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard isRendering else { return }
        render(to: update.drawable.texture, drawable: update.drawable, at: update.targetPresentationTimestamp)
    }

    private func render(to texture: MTLTexture, drawable: CAMetalDrawable? = nil, at now: Double) {
        guard now.isFinite, lastDrawTime.map({ now >= $0 }) ?? true else { return }
        renderedFrameCount += 1
        let elapsed = max(0, now - (lastDrawTime ?? now))
        lastDrawTime = now
        let followingFold = ending ? 0 : smoothing.step(at: now)
        let displayedFold = handoff.step(toward: followingFold,
                                        velocity: ending ? 0 : smoothing.velocity, elapsed: elapsed)
        renderedFold = displayedFold
        renderedVelocity = handoff.active ? handoff.velocity : (ending ? 0 : smoothing.velocity)
        if ending, !handoff.active, !fadingOut {
            // Reveal live pixels only after geometry and material reach identity.
            fadingOut = true
            fade(to: 0, duration: 0.050)
        } else if fadeDuration > 0 {
            fadeElapsed += elapsed
            let t = min(1, fadeElapsed / fadeDuration)
            opacity = fadeOrigin + (fadeTarget - fadeOrigin) * Float(t * t * (3 - 2 * t))
            if t == 1 { fadeDuration = 0 }
        }
        let finished = ending && fadingOut && opacity == 0
        let settled = (!handoff.active && !ending && displayedFold == foldRadians && fadeDuration == 0)
            || finished || progress == 0
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let command = encode(descriptor: descriptor, displayedFold: displayedFold, opacity: opacity) else { return }
        let token = transitionGeneration
        if finished, let completion = onReturnToFlat {
            onReturnToFlat = nil
            // A transparent final frame is safe to retire once GPU work is done.
            // Presentation is telemetry, never an unbounded cleanup dependency.
            command.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.transitionGeneration == token else { return }
                    completion()
                }
            }
        }
        let inputTime = sampleTime
        if timingEnabled, let drawable { drawable.addPresentedHandler { [weak self] drawable in
            let presented = drawable.presentedTime
            DispatchQueue.main.async {
                guard let self, self.transitionGeneration == token, presented > 0 else { return }
                let interval = self.previousPresentation > 0 ? (presented - self.previousPresentation) * 1000 : 0
                let age = max(0, presented - inputTime) * 1000
                if self.firstPresentationPending || interval > 25 {
                    self.timingLog.debug("presented: first=\(self.firstPresentationPending), inputAgeMs=\(age), intervalMs=\(interval)")
                }
                self.firstPresentationPending = false
                self.previousPresentation = presented
            }
        } }
        if let drawable { command.present(drawable) }
        command.commit()
        if settled { displayLink?.isPaused = true }
    }

    private func encode(descriptor: MTLRenderPassDescriptor, displayedFold: Float? = nil, opacity: Float = 1) -> MTLCommandBuffer? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        // Retain both wrappers until the GPU has finished reading the IOSurface.
        let retainedTexture = sourceTexture
        let retainedBuffer = sourceBuffer
        var sampledTexture: MTLTexture?
        if let retainedTexture, let rawTexture = CVMetalTextureGetTexture(retainedTexture),
           let texture = rawTexture.makeTextureView(pixelFormat: .bgra8Unorm_srgb) {
            if filteredTexture?.width != texture.width || filteredTexture?.height != texture.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                    width: texture.width, height: texture.height, mipmapped: true)
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
                filteredTexture = device.makeTexture(descriptor: descriptor)
                sourceNeedsFiltering = true
            }
            if sourceNeedsFiltering, var filteredTexture, let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                          sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                          to: filteredTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
                blit.endEncoding()
                // The fixed Gaussian filter decodes sRGB before averaging and
                // stores encoded mip levels. Build once, reuse through reversal
                // and eligible wake opening; no work is repeated each frame.
                gaussianPyramid.encode(commandBuffer: commandBuffer, inPlaceTexture: &filteredTexture,
                                       fallbackCopyAllocator: nil)
                self.filteredTexture = filteredTexture
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
            var dither = ditherScale
            encoder.setFragmentBytes(&dither, length: MemoryLayout<Float>.stride, index: 4)
            var alpha = opacity
            encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 3)
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
        let builtIn = NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        let backingSize = builtIn.map { $0.convertRectToBacking(NSRect(origin: .zero, size: $0.frame.size)).size }
        let environment = ProcessInfo.processInfo.environment
        let width = benchmark ? max(960, Int(environment["GLISSFORM_BENCHMARK_WIDTH"] ?? "") ?? Int(backingSize?.width ?? 2880)) : 960
        let height = benchmark ? max(600, Int(environment["GLISSFORM_BENCHMARK_HEIGHT"] ?? "") ?? Int(backingSize?.height ?? 1864)) : 600
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        guard let renderer = EffectRenderer(view: view) else { throw failure("Metal initialization failed") }
        guard !renderer.isRendering else {
            throw failure("Rendering must remain stopped before a gesture")
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
            if label == "zeroAngle" {
                let preparedTexture = renderer.filteredTexture
                renderer.pauseSnapshot()
                guard renderer.hasPreparedSnapshot, renderer.sourceBuffer === buffer,
                      renderer.filteredTexture === preparedTexture, view.isPaused else {
                    throw failure("Pausing must retain the exact source and prepared texture without drawing")
                }
                // The following zero-angle pixel comparison also checks that
                // the retained image returns unchanged, without another upload.
            }
            renderer.progress = amount
            renderer.blurScale = frost
            renderer.setLidAngle(label == "zeroAngle" ? reference : reference - Double(amount) * 80,
                                 referenceAngle: reference)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
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
                                let encoded = Double(originalPixels[py * rowBytes + px * 4 + channel]) / 255
                                let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                                expected += linear * weight
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
                        expected = 255 * (expected <= 0.0031308 ? expected * 12.92 : 1.055 * pow(expected, 1 / 2.4) - 0.055)
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
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw failure("PNG encoding failed")
            }
            let target = label == "frost52" ? outputURL : outputURL.deletingPathExtension().appendingPathExtension("\(label).png")
            try png.write(to: target)
        }
        print("PASS: stationary-plane GPU projection at 16°/40°/90°/120°, orientation, opacity, retained-frame identity, top shadow, bottom-edge blur, frost at 20°/40°/52°/80°")
        try checkMaterial(renderer: renderer)
        renderer.update(pixelBuffer: buffer)
        if benchmark {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
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
            let preparationStart = ProcessInfo.processInfo.systemUptime
            guard let preparation = renderer.encode(descriptor: pass, displayedFold: 0) else {
                throw failure("Cannot prepare benchmark pyramid")
            }
            preparation.commit()
            preparation.waitUntilCompleted()
            if let error = preparation.error { throw error }
            print(String(format: "Synthetic %dx%d image copy, Gaussian pyramid and identity: GPU %.2f ms, encode/wait %.2f ms (capture excluded)",
                         width, height, (preparation.gpuEndTime - preparation.gpuStartTime) * 1000,
                         (ProcessInfo.processInfo.systemUptime - preparationStart) * 1000))
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

    /// High-contrast and dark, flat synthetic images expose color/quantization
    /// errors that the illustrated desktop and broad blur-energy test can hide.
    private static func checkMaterial(renderer: EffectRenderer) throws {
        func failure(_ message: String) -> NSError {
            NSError(domain: "Glissform.MaterialTest", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        let width = 1024, height = 1024
        func buffer(checker: Bool, color: SIMD3<UInt8> = SIMD3(repeating: 64)) throws -> CVPixelBuffer {
            var storage: CVPixelBuffer?
            let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                             kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                      attributes as CFDictionary, &storage) == kCVReturnSuccess,
                  let storage else { throw failure("Cannot allocate material probe") }
            CVPixelBufferLockBaseAddress(storage, [])
            defer { CVPixelBufferUnlockBaseAddress(storage, []) }
            let bytes = CVPixelBufferGetBaseAddress(storage)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(storage)
            for y in 0..<height { for x in 0..<width {
                let value: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                let offset = y * rowBytes + x * 4
                bytes[offset] = checker ? value : color.x
                bytes[offset + 1] = checker ? value : color.y
                bytes[offset + 2] = checker ? value : color.z
                bytes[offset + 3] = 255
            } }
            return storage
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget]
        guard let target = renderer.device.makeTexture(descriptor: descriptor) else {
            throw failure("Cannot allocate material target")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        renderer.blurScale = 1
        renderer.setLidAngle(45, referenceAngle: 95)
        func render(degrees: Float, dither: Float = 1, opacity: Float = 1) throws -> [UInt8] {
            renderer.ditherScale = dither
            guard let command = renderer.encode(descriptor: pass, displayedFold: degrees * .pi / 180, opacity: opacity) else {
                throw failure("Cannot encode material probe")
            }
            command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return pixels
        }
        renderer.update(pixelBuffer: try buffer(checker: true))
        _ = try render(degrees: 24)
        // Read the actual prepared mip, not a separate approximation of the filter.
        let sampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: 1, height: 1, mipmapped: false)
        sampleDescriptor.storageMode = .shared
        guard let sample = renderer.device.makeTexture(descriptor: sampleDescriptor),
              let pyramid = renderer.filteredTexture,
              let command = renderer.commandQueue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw failure("Cannot inspect Gaussian color probe")
        }
        blit.copy(from: pyramid, sourceSlice: 0, sourceLevel: 1,
                  sourceOrigin: MTLOrigin(x: width / 4, y: height / 4, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: sample, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var averaged = [UInt8](repeating: 0, count: 4)
        sample.getBytes(&averaged, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        guard averaged.prefix(3).allSatisfy({ abs(Int($0) - 188) <= 1 }) else {
            throw failure("Gaussian filtering must average black and white in linear light: \(averaged)")
        }
        // Fine angle sweeps cross multiple mip transitions without sample jumps.
        for degrees: Float in [1, 3, 6, 12, 24, 40, 60] {
            let before = try render(degrees: degrees - 0.001)
            let after = try render(degrees: degrees + 0.001)
            for y in stride(from: 128, to: 896, by: 32) {
                let offset = (y * width + width / 2) * 4
                guard abs(Int(before[offset]) - Int(after[offset])) <= 2 else {
                    throw failure("Material discontinuity near \(degrees) degrees at row \(y): \(before[offset]) -> \(after[offset])")
                }
            }
        }
        renderer.update(pixelBuffer: try buffer(checker: false))
        let identity = try render(degrees: 0)
        guard stride(from: 0, to: identity.count, by: 4).allSatisfy({ identity[$0] == 64 }) else {
            throw failure("Dithering must leave the zero-angle image unchanged")
        }
        let quantized = try render(degrees: 50, dither: 0)
        let dithered = try render(degrees: 50)
        guard try render(degrees: 50) == dithered else { throw failure("Gradient dithering must be stable between frames") }
        let fraction = 50.0 / 91.0
        let progress = fraction * fraction * (3 - 2 * fraction)
        let source = pow((64.0 / 255 + 0.055) / 1.055, 2.4)
        var quantizedError = 0.0, ditheredError = 0.0
        // Average one complete threshold tile, excluding the projected borders.
        for top in stride(from: 256, to: 768, by: 8) {
            var ideal = 0.0, plain = 0.0, smooth = 0.0
            for y in top..<(top + 8) {
                let uv = (Double(y) + 0.5) / Double(height)
                let t = min(1, max(0, (uv - 0.05) / 0.95))
                let darkness = pow(progress, 2.2) * (1 - t * t * (3 - 2 * t))
                let linear = source * (1 - darkness)
                ideal += 255 * (linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055) / 8
                for x in (width / 2 - 32)..<(width / 2 + 32) {
                    plain += Double(quantized[(y * width + x) * 4]) / 512
                    smooth += Double(dithered[(y * width + x) * 4]) / 512
                }
            }
            quantizedError += pow(plain - ideal, 2)
            ditheredError += pow(smooth - ideal, 2)
        }
        guard ditheredError < quantizedError * 0.4 else {
            throw failure("Fixed dithering must reduce dark-gradient rounding error: \(quantizedError) -> \(ditheredError)")
        }
        print(String(format: "PASS: linear-light Gaussian average, material continuity, exact identity, stable dark-gradient dithering (tile error %.4f -> %.4f)",
                     quantizedError, ditheredError))
        // CAMetalLayer's sRGB bytes must contain encoded premultiplied colors.
        // Merely multiplying linear white by 0.5 before an sRGB target would
        // incorrectly store RGB 188 with alpha 128, producing a bright fade.
        let colors: [SIMD3<UInt8>] = [SIMD3(0, 0, 0), SIMD3(255, 255, 255), SIMD3(255, 0, 0),
                                      SIMD3(0, 255, 0), SIMD3(0, 0, 255), SIMD3(0, 96, 255)]
        for color in colors {
            renderer.update(pixelBuffer: try buffer(checker: false, color: color))
            for degrees: Float in [0, 24] {
                let opaque = try render(degrees: degrees)
                for alpha: Float in [0, 0.25, 0.5, 1] {
                    let pixels = try render(degrees: degrees, opacity: alpha)
                    if alpha == 0 {
                        guard pixels.allSatisfy({ $0 == 0 }) else { throw failure("Transparent output must be exactly zero") }
                    }
                    for (x, y) in [(0, 0), (width / 2, height / 2), (width - 1, height - 1)] {
                        let offset = (y * width + x) * 4
                        guard abs(Int(pixels[offset + 3]) - Int((255 * alpha).rounded())) <= 1 else {
                            throw failure("Incorrect output alpha")
                        }
                        for channel in 0..<3 {
                            let expected = Int((Float(opaque[offset + channel]) * alpha).rounded())
                            guard abs(Int(pixels[offset + channel]) - expected) <= 1 else {
                                throw failure("sRGB premultiplication mismatch: color \(color), angle \(degrees), alpha \(alpha), channel \(channel)")
                            }
                        }
                    }
                }
            }
        }
        print("PASS: encoded premultiplied sRGB output for black, white and saturated colors at alpha 0/0.25/0.5/1")
        renderer.ditherScale = 1
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
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
        let symbols: [IconlySymbol] = [.copy, .shieldDone, .pause, .play, .laptop, .lock, .memory]
        for index in 0..<7 {
            let x = 229 + index * 73
            card(NSRect(x: x, y: 38, width: 64, height: 54), colors[index], radius: 13)
            symbols[index].image.draw(in: NSRect(x: x + 15, y: 49, width: 34, height: 32))
        }
        NSGraphicsContext.restoreGraphicsState()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        renderer.update(pixelBuffer: buffer)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
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
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
    float4 layerColor(float3 linearColor, float opacity) {
        if (opacity <= 0.0f) return float4(0);
        if (opacity >= 1.0f) return float4(linearColor, 1);
        // The layer is tagged sRGB and consumes encoded premultiplied bytes.
        // Premultiply in that storage space, then undo the transfer here because
        // the sRGB render attachment applies it once more when storing the pixel.
        float3 encoded = select(linearColor * 12.92f,
                                1.055f * pow(linearColor, float3(1.0f / 2.4f)) - 0.055f,
                                linearColor > 0.0031308f) * opacity;
        float3 forAttachment = select(encoded / 12.92f,
                                      pow((encoded + 0.055f) / 1.055f, float3(2.4f)),
                                      encoded > 0.04045f);
        return float4(forAttachment, opacity);
    }
    fragment float4 hingeFragment(Vertex in [[stage_in]], texture2d<float> desktop [[texture(0)]],
                                   constant float4 &uniforms [[buffer(0)]], constant float &frost [[buffer(1)]],
                                   constant float2 &eye [[buffer(2)]], constant float &opacity [[buffer(3)]],
                                   constant float &ditherScale [[buffer(4)]]) {
        constexpr sampler sampling(coord::normalized, address::clamp_to_zero, filter::linear, mip_filter::linear);
        float theta = max(0.0f, uniforms.w);
        // Only the displayed angle controls effect strength; a raw sensor
        // threshold must never switch the shader on or off during a handoff.
        if (theta == 0.0f) return layerColor(desktop.sample(sampling, in.uv, level(0)).rgb, opacity);
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
        // A controlled Gaussian pyramid is prepared once per screenshot. Its
        // variance grows as (4^level - 1) / 3. Split the desired variance between
        // a finer pyramid level and a small weighted kernel, so magnifying a
        // coarse mip never turns small colored shapes into interpolation cells.
        // Both approach the untouched base level continuously at zero.
        float lod = 0.5f * log2(1.0f + 0.5f * radius * radius);
        float2 step = radius * 0.577350269f / max(uniforms.yz, float2(1));
        const float weights[] = {0.25f, 0.5f, 0.25f};
        float3 color = float3(0);
        for (uint y = 0; y < 3; ++y) {
            for (uint x = 0; x < 3; ++x) {
                float2 offset = float2(float(x) - 1.0f, float(y) - 1.0f) * step;
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
        color *= 1.0f - darkness;
        // A fixed 8x8 ordered threshold spreads the final 8-bit rounding over
        // neighboring pixels. Scale in linear light by the sRGB transfer slope:
        // the perturbation stays below half an encoded code value. Static screen
        // coordinates avoid temporal noise; zero identity and black stay exact.
        uint2 position = uint2(in.position.xy);
        uint rank = 0;
        for (uint bit = 0; bit < 3; ++bit) {
            rank |= (((position.x >> bit) ^ (position.y >> bit)) & 1u) << (5u - 2u * bit);
            rank |= ((position.y >> bit) & 1u) << (4u - 2u * bit);
        }
        float noise = ((float(rank) + 0.5f) / 64.0f - 0.5f) * ditherScale / 255.0f;
        float3 slope = select(float3(1.0f / 12.92f),
                             (2.4f / 1.055f) * pow(color, float3(1.4f / 2.4f)), color > 0.0031308f);
        color = select(float3(0), clamp(color + noise * slope, 0.0f, 1.0f), color > 0);
        return layerColor(color, opacity);
    }
    """
}
