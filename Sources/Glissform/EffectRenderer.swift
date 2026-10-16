import AppKit
import CoreVideo
import CoreImage
import CoreImage.CIFilterBuiltins
import MetalKit
import QuartzCore
import OSLog
import MetalPerformanceShaders

/// Draws an opaque, angle-driven desktop transition. All public instance calls use the main queue.
final class EffectRenderer: NSObject, MTKViewDelegate, CAMetalDisplayLinkDelegate {
    enum CompletionMode {
        case lid, assisted, pause, disabled
        var hasConnectionFeedback: Bool { self != .disabled }
    }
    private weak var view: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let gaussianPyramid: MPSImageGaussianPyramid
    private let blurContext: CIContext
    private let blurColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private final class ProjectionSlot {
        let texture: MTLTexture
        var inUse = false
        init(texture: MTLTexture) { self.texture = texture }
    }
    private var textureCache: CVMetalTextureCache?
    private var sourceTexture: CVMetalTexture?
    private var sourceBuffer: CVPixelBuffer?
    private var filteredTexture: MTLTexture?
    private var projectionSlots: [ProjectionSlot] = []
    private var screenBlurMask: CIImage?
    private var sourceNeedsFiltering = true
    private var foldRadians: Float = 0
    private var projectionReferenceAngle = 90.0
    private var fullClosureRadians: Float = 1
    private var smoothing = MotionSmoothing()
    private var lastDrawTime: TimeInterval?
    private var handoff = HandoffTransition()
    private var openingContinuation = OpeningContinuation()
    private var pendingOpeningSpeed: Double?
    private static let connectionGlowMaximumSpread: Float = 0.032
    private static let connectionGlowApproachIntensity: Float = 1
    private static let connectionGlowContactIntensity: Float = 1.75
    // The final damped tail is already visually flat. Mark contact without
    // clipping that tail or waiting for its much stricter numerical snap.
    private static let lidConnectionFold = Float(0.1 * Double.pi / 180)
    private var connectionFeedbackActive = false
    var connectionEffectEnabled = true {
        didSet {
            guard !connectionEffectEnabled else { return }
            connectionFeedbackActive = false
            onConnectionSchedule = nil
            connectionPeakTime = nil
            connectionSchedulePending = false
            connectionScheduleRequestedAt = nil
            connectionGlowSpread = 0
            connectionGlowReleaseStart = 0
            connectionGlowPulsing = false
            connectionGlowReleasing = false
            connectionGlowIntensity = Self.connectionGlowApproachIntensity
            connectionGlowOpacity = 0
        }
    }
    private var pauseGlowRange: Float = 0
    private var connectionGlowSpread: Float = 0
    private var connectionGlowIntensity = EffectRenderer.connectionGlowApproachIntensity
    private var connectionGlowOpacity: Float = 1
    private var connectionGlowReleaseOpacity: Float = 1
    private var connectionGlowReleaseStart: Float = 0
    private var connectionGlowReleaseIntensity = EffectRenderer.connectionGlowApproachIntensity
    private var connectionGlowPulsing = false
    private var connectionGlowReleaseElapsed: Double = 0
    private var connectionGlowReleaseDuration: Double = 0.24
    private var connectionGlowReleasing = false
    private var programmaticReturn = ProgrammaticReturn()
    private var completionMode: CompletionMode?
    private var renderedFold: Float = 0
    private var ending: Bool { completionMode != nil }
    private var lastMotionAdvanceTime: Double?
    private var transitionGeneration = 0
    private var onReturnToFlat: (() -> Void)?
    private var onConnectionSchedule: ((Double, @escaping (Double?) -> Void) -> Void)?
    private var connectionPeakTime: Double?
    private var connectionSchedulePending = false
    private var connectionScheduleRequestedAt: Double?
    private var onLiveDesktop: (() -> Void)?
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
    var isFinishingWithLid: Bool { completionMode == .lid }
    var manualCompletionIsAdvancing: Bool {
        isFinishingWithLid && isRendering
            && ProcessInfo.processInfo.systemUptime - (lastMotionAdvanceTime ?? 0) < 0.250
    }
    var connectionCompletionIsAdvancing: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard completionMode?.hasConnectionFeedback == true, isRendering else { return false }
        if now - (lastMotionAdvanceTime ?? 0) < 0.250 { return true }
        // A ready display may hold the rim briefly for the audio route. This is
        // bounded and requires fresh frames, so occlusion still releases input.
        guard connectionFeedbackActive, let requested = connectionScheduleRequestedAt,
              now - requested < 1.5, now - (lastDrawTime ?? 0) < 0.250 else { return false }
        return connectionSchedulePending || now < (connectionPeakTime ?? 0)
    }

    var hasPreparedSnapshot: Bool {
        sourceBuffer != nil && sourceTexture != nil && filteredTexture != nil && !sourceNeedsFiltering
    }

    func beginAnimation(opening: Bool = false) {
        let interruptedReturn = ending
        let interruptedLidCompletion = isFinishingWithLid
        releaseConnectionGlow()
        transitionGeneration += 1
        completionMode = nil
        connectionFeedbackActive = false
        fadingOut = false
        onReturnToFlat = nil
        onConnectionSchedule = nil
        connectionPeakTime = nil
        connectionSchedulePending = false
        connectionScheduleRequestedAt = nil
        onLiveDesktop = nil
        openingContinuation = OpeningContinuation()
        pendingOpeningSpeed = nil
        // Reclosing during manual completion is still the same lid gesture.
        // Keep its filter and any existing entrance handoff exactly as they are.
        if !interruptedLidCompletion && (!opening || interruptedReturn) {
            handoff.begin(from: renderedFold, velocity: renderedVelocity, holdFirstFrame: false)
        }
        fade(to: 1, duration: opening ? 0.050 : (opacity < 1 ? 0.040 : 0))
        scheduleSettling()
    }

    func finishAnimation(_ mode: CompletionMode, openingSpeed: Double = 0,
                         onConnectionSchedule: ((Double, @escaping (Double?) -> Void) -> Void)? = nil,
                         onLiveDesktop: (() -> Void)? = nil,
                         completion: @escaping () -> Void) {
        transitionGeneration += 1
        completionMode = mode
        connectionFeedbackActive = mode.hasConnectionFeedback && connectionEffectEnabled
        self.onConnectionSchedule = connectionFeedbackActive ? onConnectionSchedule : nil
        connectionPeakTime = nil
        connectionSchedulePending = false
        connectionScheduleRequestedAt = nil
        onReturnToFlat = completion
        self.onLiveDesktop = mode.hasConnectionFeedback ? onLiveDesktop : nil
        fadingOut = false
        pendingOpeningSpeed = nil
        pauseGlowRange = mode == .pause || mode == .lid
            ? min(max(0, renderedFold), Float(OpeningAssist.remainingDegrees * .pi / 180)) : 0
        if connectionFeedbackActive {
            connectionGlowSpread = 0
            connectionGlowIntensity = Self.connectionGlowApproachIntensity
            connectionGlowOpacity = 1
            connectionGlowReleaseStart = 0
            connectionGlowPulsing = false
            connectionGlowReleasing = false
        }
        switch mode {
        case .lid:
            // Zero is an ordinary sensor target. Do not restart the trajectory,
            // change its damping, or detach the final degree from the lid.
            break
        case .assisted:
            // The trigger's newest reading has been ingested, but has not yet
            // been drawn. Present that last lid-driven frame before taking its
            // position, speed and acceleration into the continuation.
            pendingOpeningSpeed = openingSpeed
            openingContinuation = OpeningContinuation()
        case .pause:
            openingContinuation = OpeningContinuation()
            handoff.begin(from: renderedFold, velocity: renderedVelocity,
                          duration: HandoffTransition.pauseRestorationDuration(for: renderedFold),
                          holdFirstFrame: false, curve: .pauseRestoration)
        case .disabled:
            releaseConnectionGlow()
            openingContinuation = OpeningContinuation()
            programmaticReturn.begin(from: renderedFold, velocity: renderedVelocity)
            handoff = HandoffTransition()
        }
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

    private func releaseConnectionGlow(duration: Double = 0.24, pulseAtContact: Bool = false) {
        connectionGlowReleaseStart = connectionGlowSpread
        connectionGlowReleaseIntensity = connectionGlowIntensity
        connectionGlowReleaseOpacity = connectionGlowOpacity
        connectionGlowPulsing = pulseAtContact
        connectionGlowReleaseElapsed = 0
        connectionGlowReleaseDuration = duration
        connectionGlowReleasing = true
    }

    private static func glowEase(_ fraction: Float) -> Float {
        // Evaluate in Double so a near-flat angular approach cannot make the
        // Float quintic oscillate by a rounding step near its upper endpoint.
        let t = Double(min(1, max(0, fraction)))
        return Float(min(1, max(0, t * t * t * (10 + t * (-15 + 6 * t)))))
    }

    /// Releases promptly, then trails off with zero velocity at both ends.
    private static func glowSettle(_ fraction: Double) -> Float {
        let t = min(1, max(0, fraction))
        return Float(pow(1 - t, 3) * (1 + 3 * t))
    }

    private static func glowPulse(timeFromPeak: Double) -> Float {
        if timeFromPeak < 0 {
            return glowEase(Float(1 + timeFromPeak / ConnectionFeedbackTiming.glowAttack))
        }
        return glowSettle(timeFromPeak / ConnectionFeedbackTiming.decay)
    }

    private func scheduleSettling() {
        guard progress > 0, sourceBuffer != nil else { return }
        if !isRendering { lastDrawTime = ProcessInfo.processInfo.systemUptime }
        ensureDisplayLink()
        displayLink?.isPaused = false
    }
    private var blurScale: Float = 1 // Set to zero only for geometric GPU validation.
    var blurEnabled = true {
        didSet {
            if blurEnabled != oldValue { scheduleSettling() }
        }
    }
    var blurStrength: BlurStrength = .defaultStrength {
        didSet {
            if blurStrength != oldValue { scheduleSettling() }
        }
    }
    private var ditherScale: Float = 1 // Disable only for the dark-gradient comparison.

    /// The reference desktop is a fixed plane at the angle where closure starts.
    /// Camera distance/height are in screen-height units, for a normal seated view.
    func setLidAngle(_ angle: Double, referenceAngle: Double,
                     sampleTime: Double = ProcessInfo.processInfo.systemUptime) {
        guard angle.isFinite, referenceAngle.isFinite else { return }
        self.sampleTime = sampleTime
        projectionReferenceAngle = referenceAngle
        fullClosureRadians = ScreenProjection.foldRadians(lidAngle: 4, referenceAngle: referenceAngle)
        let next = ScreenProjection.foldRadians(lidAngle: angle, referenceAngle: referenceAngle)
        smoothing.ingest(target: next, at: sampleTime)
        guard smoothing.target != foldRadians else { return }
        foldRadians = smoothing.target
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
        self.blurContext = CIContext(mtlDevice: device)
        self.gaussianPyramid = MPSImageGaussianPyramid(device: device)
        // The shader applies one continuous soft image boundary. Clamping the
        // pyramid itself avoids baking separate dark borders into every mip.
        self.gaussianPyramid.edgeMode = .clamp
        self.view = view
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            return nil
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // The screen-space finishing blur writes through Core Image into the
        // drawable after Metal has rendered the projected screenshot.
        view.framebufferOnly = false
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

    /// Prepare the latest measured fold for closing or waking before reveal.
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
        let initialFold = foldRadians
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
        openingContinuation = OpeningContinuation()
        pendingOpeningSpeed = nil
        pauseGlowRange = 0
        connectionGlowSpread = 0
        connectionGlowIntensity = Self.connectionGlowApproachIntensity
        connectionGlowOpacity = 1
        connectionGlowReleaseOpacity = 1
        connectionGlowReleaseStart = 0
        connectionGlowReleaseIntensity = Self.connectionGlowApproachIntensity
        connectionGlowPulsing = false
        connectionGlowReleaseElapsed = 0
        connectionGlowReleasing = false
        programmaticReturn = ProgrammaticReturn()
        completionMode = nil
        connectionFeedbackActive = false
        lastMotionAdvanceTime = nil
        transitionGeneration += 1
        onReturnToFlat = nil
        onLiveDesktop = nil
        onConnectionSchedule = nil
        connectionPeakTime = nil
        connectionSchedulePending = false
        connectionScheduleRequestedAt = nil
    }

    func clear() {
        pauseSnapshot()
        sourceTexture = nil
        sourceBuffer = nil
        filteredTexture = nil
        projectionSlots.removeAll()
        screenBlurMask = nil
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

    private func lidConnectionTime(after now: Double) -> Double? {
        guard foldRadians == 0 else { return nil }
        if renderedFold <= Self.lidConnectionFold && renderedVelocity <= 0 { return now }
        // Only forecast feedback. Value copies leave the visible smoothing,
        // velocity and entrance handoff untouched. A reclose cancels the cue.
        var projectedSmoothing = smoothing
        var projectedHandoff = handoff
        let frame = 1 / Double(frameRate)
        for index in 1...Int(ceil(2 / frame)) {
            let time = now + Double(index) * frame
            let target = projectedSmoothing.step(at: time)
            let fold = projectedHandoff.step(toward: target,
                velocity: projectedSmoothing.velocity, elapsed: frame)
            if fold <= Self.lidConnectionFold && projectedHandoff.velocity <= 0 { return time }
        }
        return nil
    }

    private func advanceMotion(at now: Double) {
        let elapsed = max(0, now - (lastDrawTime ?? now))
        lastDrawTime = now
        let previousVelocity = renderedVelocity
        let followsLid = !ending || isFinishingWithLid || pendingOpeningSpeed != nil
        let followingFold = followsLid ? smoothing.step(at: now) : 0
        let followingVelocity = followsLid ? smoothing.velocity : 0
        if completionMode == .disabled {
            renderedFold = programmaticReturn.step(elapsed: elapsed)
            renderedVelocity = programmaticReturn.velocity
        } else if completionMode == .assisted && pendingOpeningSpeed == nil {
            renderedFold = openingContinuation.step(elapsed: elapsed)
            renderedVelocity = openingContinuation.velocity
        } else {
            renderedFold = handoff.step(toward: followingFold, velocity: followingVelocity, elapsed: elapsed)
            renderedVelocity = handoff.active ? handoff.velocity : followingVelocity
        }
        let renderedAcceleration = elapsed > 0 && elapsed <= 0.100
            ? (renderedVelocity - previousVelocity) / elapsed : 0
        if let speed = pendingOpeningSpeed {
            openingContinuation.begin(from: renderedFold, velocity: renderedVelocity,
                                      acceleration: renderedAcceleration, observedSpeed: speed)
            pendingOpeningSpeed = nil
            handoff = HandoffTransition()
        }
        let atIdentity = renderedFold == 0 && renderedVelocity == 0 && !handoff.active
            && (completionMode != .disabled || !programmaticReturn.active)
            && (!isFinishingWithLid || foldRadians == 0)
        let atConnection = atIdentity || (isFinishingWithLid && foldRadians == 0
            && renderedFold <= Self.lidConnectionFold && renderedVelocity <= 0)
        // A sensor sample may jump past the assisted region. Keep the ordinary
        // lid trajectory intact and mark its visually flat contact without
        // waiting through the tiny, still-moving numerical settling tail.
        // Queue audio during the return so output lead time is absorbed before
        // contact instead of holding a dim rim over an already-flat image.
        let lidContact = connectionFeedbackActive && connectionPeakTime == nil && isFinishingWithLid
            ? lidConnectionTime(after: now) : nil
        if connectionFeedbackActive && connectionPeakTime == nil && (!isFinishingWithLid || lidContact != nil) {
            let remaining = isFinishingWithLid ? max(0, (lidContact ?? now) - now) : (completionMode == .assisted
                ? openingContinuation.remainingDuration : handoff.remainingDuration)
            // Target an actual display frame, including the pulse's rounded attack.
            let frame = 1 / Double(frameRate)
            let contact = isFinishingWithLid ? (lidContact ?? now) : now + ceil(remaining / frame) * frame
            let peak = contact + ceil(ConnectionFeedbackTiming.attack / frame) * frame
            connectionPeakTime = peak
            if let schedule = onConnectionSchedule {
                onConnectionSchedule = nil
                connectionSchedulePending = true
                connectionScheduleRequestedAt = now
                let token = transitionGeneration
                schedule(peak) { [weak self] scheduledPeak in
                    guard let self, self.transitionGeneration == token, self.connectionFeedbackActive else { return }
                    self.connectionPeakTime = max(peak, scheduledPeak ?? peak)
                    self.connectionSchedulePending = false
                }
            }
        }
        if connectionFeedbackActive && !connectionGlowReleasing {
            let t: Float
            if completionMode == .assisted {
                t = openingContinuation.completionFraction
            } else if isFinishingWithLid && atConnection {
                // A very shallow gesture can already be flat on its first
                // return frame. It still has one visible connection to mark.
                t = 1
            } else {
                // Lid/Pause/Escape may start at a deep fold. Keep the glow hidden
                // until only five visible degrees remain; shallow returns use
                // their smaller starting fold so the glow still begins at zero.
                t = pauseGlowRange > 0
                    ? min(1, max(0, 1 - renderedFold / pauseGlowRange)) : handoff.completionFraction
            }
            // Gather toward contact while the final part of the approach
            // gently builds toward the same scheduled click peak.
            let ease = Self.glowEase(t)
            connectionGlowSpread = Self.connectionGlowMaximumSpread * ease
            connectionGlowOpacity = ease
            if let peak = connectionPeakTime, !connectionSchedulePending {
                connectionGlowIntensity = Self.connectionGlowApproachIntensity
                    + (Self.connectionGlowContactIntensity - Self.connectionGlowApproachIntensity)
                    * Self.glowPulse(timeFromPeak: now - peak)
            }
        } else if connectionGlowReleasing && connectionGlowReleaseStart > 0 {
            if connectionGlowPulsing, let peak = connectionPeakTime {
                connectionGlowReleaseElapsed = connectionSchedulePending ? 0
                    : max(0, now - (peak - ConnectionFeedbackTiming.attack))
            } else {
                connectionGlowReleaseElapsed += elapsed
            }
            let t = Float(min(1, connectionGlowReleaseElapsed / connectionGlowReleaseDuration))
            let remaining = Self.glowSettle(Double(t))
            // Let the light disappear while its footprint settles gently.
            // Keeping some width at zero opacity avoids a bright final pinch.
            connectionGlowSpread = t == 1 ? 0
                : connectionGlowReleaseStart * (0.55 + 0.45 * remaining)
            if connectionGlowPulsing {
                let timeFromPeak = connectionPeakTime.map { now - $0 }
                    ?? (connectionGlowReleaseElapsed - ConnectionFeedbackTiming.attack)
                let pulse = connectionSchedulePending ? 0 : Self.glowPulse(timeFromPeak: timeFromPeak)
                connectionGlowIntensity = Self.connectionGlowApproachIntensity
                    + (Self.connectionGlowContactIntensity - Self.connectionGlowApproachIntensity) * pulse
                connectionGlowOpacity = connectionSchedulePending ? connectionGlowReleaseOpacity
                    : connectionGlowReleaseOpacity * Self.glowSettle(
                        max(0, timeFromPeak) / (connectionGlowReleaseDuration - ConnectionFeedbackTiming.attack))
            } else {
                // A reversal cancels any pending rise, gently settling the
                // brightness already visible instead of replaying contact.
                let settle = Self.glowEase(Float(connectionGlowReleaseElapsed / 0.080))
                connectionGlowIntensity = Self.connectionGlowApproachIntensity
                    + (connectionGlowReleaseIntensity - Self.connectionGlowApproachIntensity) * (1 - settle)
                connectionGlowOpacity = connectionGlowReleaseOpacity * remaining
            }
            if t == 1 { connectionGlowReleaseStart = 0 }
        }
        if ending, atConnection, connectionFeedbackActive, !connectionGlowReleasing {
            releaseConnectionGlow(duration: ConnectionFeedbackTiming.retreat, pulseAtContact: true)
        }
        if ending, atIdentity, !fadingOut {
            // Reveal live pixels only after geometry and material reach identity.
            fadingOut = true
            fade(to: 0, duration: 0.050)
        } else if fadeDuration > 0 {
            fadeElapsed += elapsed
            let t = min(1, fadeElapsed / fadeDuration)
            opacity = fadeOrigin + (fadeTarget - fadeOrigin) * Float(t * t * (3 - 2 * t))
            if t == 1 { fadeDuration = 0 }
        }
    }

    private func render(to texture: MTLTexture, drawable: CAMetalDrawable? = nil, at now: Double) {
        guard now.isFinite, lastDrawTime.map({ now >= $0 }) ?? true else { return }
        renderedFrameCount += 1
        let previousFold = renderedFold, previousOpacity = opacity, previousGlow = connectionGlowSpread
        let previousIntensity = connectionGlowIntensity
        let previousGlowOpacity = connectionGlowOpacity
        advanceMotion(at: now)
        let displayedFold = renderedFold
        let finished = ending && fadingOut && opacity == 0
            && (!connectionFeedbackActive || connectionGlowSpread == 0)
        let settled = (!handoff.active && !ending && displayedFold == foldRadians && fadeDuration == 0
                       && connectionGlowSpread == 0)
            || finished || progress == 0
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let command = encode(descriptor: descriptor, displayedFold: displayedFold, opacity: opacity) else { return }
        if renderedFold != previousFold || opacity != previousOpacity || connectionGlowSpread != previousGlow
            || connectionGlowIntensity != previousIntensity || connectionGlowOpacity != previousGlowOpacity {
            lastMotionAdvanceTime = ProcessInfo.processInfo.systemUptime
        }
        let token = transitionGeneration
        if fadingOut, opacity == 0, let reveal = onLiveDesktop {
            onLiveDesktop = nil
            command.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.transitionGeneration == token else { return }
                    reveal()
                }
            }
        }
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
        let visibleAngle = displayedFold ?? foldRadians
        let fraction = min(1, max(0, visibleAngle / max(0.001, fullClosureRadians)))
        let visibleProgress = fraction * fraction * (3 - 2 * fraction)
        let frostAmount = pow(visibleProgress, 0.7)
        let strengthScale = blurStrength.scale(at: fraction)
        let target = descriptor.colorAttachments[0].texture
        // A modest even Gaussian avoids the radius bands seen with a strong
        // masked variable blur. Its blend strength still follows the height.
        let screenBlurRadius = min(Float(target?.height ?? 0) * 0.008, 24)
            * frostAmount * 0.8 * strengthScale
        var blurSlot: ProjectionSlot?
        var blurImage: CIImage?
        if sampledTexture != nil, visibleAngle > 0, opacity > 0, blurEnabled, blurScale > 0,
           screenBlurRadius >= 0.5, let target, target.usage.contains(.shaderWrite),
           let slot = acquireProjectionSlot(width: target.width, height: target.height),
           let mask = screenBlurMask,
           let textureImage = CIImage(mtlTexture: slot.texture, options: [.colorSpace: blurColorSpace]) {
            let bounds = CGRect(x: 0, y: 0, width: target.width, height: target.height)
            // Core Image and the Metal drawable use opposite vertical origins.
            // Orient the projection before blurring so the image and mask agree.
            let projected = textureImage.transformed(by: CGAffineTransform(
                translationX: 0, y: CGFloat(target.height)).scaledBy(x: 1, y: -1))
                .cropped(to: bounds)
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = projected.clampedToExtent()
            filter.radius = screenBlurRadius
            if let softened = filter.outputImage {
                // The projection covers the whole target with uniform alpha.
                // Eroding that alpha yields the same constant and needlessly
                // adds a full-screen morphology pass to every moving frame.
                // During a fade, preserve the old two-blend result by scaling
                // the height mask by that same constant opacity.
                let effectiveMask: CIImage
                if opacity < 1 {
                    let scale = CGFloat(opacity)
                    effectiveMask = mask.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0)
                    ])
                } else {
                    effectiveMask = mask
                }
                blurImage = softened.cropped(to: bounds).applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: projected,
                    kCIInputMaskImageKey: effectiveMask
                ]).cropped(to: bounds)
            }
            if blurImage != nil { blurSlot = slot }
            else { slot.inUse = false }
        }
        let renderDescriptor: MTLRenderPassDescriptor
        if let blurSlot {
            let offscreen = MTLRenderPassDescriptor()
            offscreen.colorAttachments[0].texture = blurSlot.texture
            offscreen.colorAttachments[0].loadAction = .clear
            offscreen.colorAttachments[0].clearColor = descriptor.colorAttachments[0].clearColor
            offscreen.colorAttachments[0].storeAction = .store
            renderDescriptor = offscreen
        } else { renderDescriptor = descriptor }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
            blurSlot?.inUse = false
            return nil
        }
        if let texture = sampledTexture {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            var uniforms = SIMD4<Float>(visibleProgress, Float(texture.width), Float(texture.height), visibleAngle)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            var frost = blurEnabled ? blurScale * strengthScale : 0
            encoder.setFragmentBytes(&frost, length: MemoryLayout<Float>.stride, index: 1)
            var eye = SIMD2<Float>(ScreenProjection.eyeDistance, ScreenProjection.eyeHeight)
            encoder.setFragmentBytes(&eye, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            var imageShape = SIMD2<Float>(ScreenProjection.imageRadians(for: visibleAngle, referenceAngle: projectionReferenceAngle),
                                          ScreenProjection.topWidth(for: visibleAngle))
            encoder.setFragmentBytes(&imageShape, length: MemoryLayout<SIMD2<Float>>.stride, index: 5)
            var dither = ditherScale
            encoder.setFragmentBytes(&dither, length: MemoryLayout<Float>.stride, index: 4)
            var alpha = opacity
            encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 3)
            var glow = SIMD4<Float>(connectionGlowSpread, Float(target?.width ?? texture.width),
                                    Float(target?.height ?? texture.height), connectionGlowIntensity)
            encoder.setFragmentBytes(&glow, length: MemoryLayout<SIMD4<Float>>.stride, index: 6)
            var glowOpacity = connectionGlowOpacity
            encoder.setFragmentBytes(&glowOpacity, length: MemoryLayout<Float>.stride, index: 7)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        if let blurSlot, let blurImage, let target {
            blurContext.render(blurImage, to: target, commandBuffer: commandBuffer,
                               bounds: CGRect(x: 0, y: 0, width: target.width, height: target.height),
                               colorSpace: blurColorSpace)
            commandBuffer.addCompletedHandler { [blurSlot] _ in
                DispatchQueue.main.async { blurSlot.inUse = false }
            }
        }
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(retainedTexture) {}
            withExtendedLifetime(retainedBuffer) {}
        }
        return commandBuffer
    }

    private func acquireProjectionSlot(width: Int, height: Int) -> ProjectionSlot? {
        if projectionSlots.first?.texture.width != width || projectionSlots.first?.texture.height != height {
            projectionSlots.removeAll()
            screenBlurMask = nil
        }
        if screenBlurMask == nil {
            let gradient = CIFilter.smoothLinearGradient()
            gradient.point0 = CGPoint(x: 0, y: 0)
            gradient.point1 = CGPoint(x: 0, y: height)
            // Alongside the 20% smaller radius, this gives the hinge region
            // about 30% less finishing blur than before; the top gets 20% less.
            gradient.color0 = CIColor(red: 0.57, green: 0.57, blue: 0.57)
            gradient.color1 = CIColor(red: 1, green: 1, blue: 1)
            screenBlurMask = gradient.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        }
        if let slot = projectionSlots.first(where: { !$0.inUse }) {
            slot.inUse = true
            return slot
        }
        // Keep GPU work bounded if the display is already behind.
        guard projectionSlots.count < 3 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let slot = ProjectionSlot(texture: texture)
        slot.inUse = true
        projectionSlots.append(slot)
        return slot
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
        if !benchmark {
            try checkManualCompletion(renderer: renderer)
            renderer.pauseSnapshot()
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Sharp intermediate frames test the image projection independently of
        // the frosting, including the softened geometry at deep folds.
        let cases: [(Float, Float, Double, String)] = [(0, 1, 85, "clear"), (0.5, 1, 85, "zeroAngle"),
            (0.2, 0, 85, "projection16"), (0.5, 0, 85, "projection40"),
            (0.5, 1, 85, "blurOff40"),
            (0.5625, 0, 105, "projection45from105"),
            (1.125, 0, 105, "projection90from105"),
            (1.125, 0, 100, "projection90"), (1.5, 0, 130, "projection120"),
            (0.25, 1, 85, "frost20"), (0.5, 1, 85, "frost40"),
            (0.5, 1, 85, "frostRegular40"), (0.5, 1, 85, "frostSubtle40"),
            (0.65, 1, 85, "frost52"),
            (1, 1, 85, "frost80"), (1.0125, 1, 85, "fullShadow")]
        var sharpBottomEdgeEnergy: Double?
        var sharpProjectionPixels: [UInt8]?
        var strengthPixels: [String: [UInt8]] = [:]
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
            renderer.blurEnabled = label != "blurOff40"
            renderer.blurStrength = label == "frostRegular40" ? .regular
                : label == "frostSubtle40" ? .subtle : .high
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
            if label == "projection40" { sharpProjectionPixels = rendered }
            if label == "blurOff40", rendered != sharpProjectionPixels {
                throw failure("Disabling blur must retain the sharp projection and shadow")
            }
            if ["frost40", "frostRegular40", "frostSubtle40"].contains(label) {
                strengthPixels[label] = rendered
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
                let physicalAngle = Float(amount) * 80 * .pi / 180
                let theta = Double(ScreenProjection.imageRadians(for: physicalAngle, referenceAngle: reference))
                for (x, y) in [(17, 19), (911, 23), (29, 563), (901, 557), (340, 230), (620, 390)] {
                    // Independent ray/plane intersection in screen-height units.
                    let heightFromHinge = 1 - (Double(y) + 0.5) / Double(height)
                    let topWidth = Double(ScreenProjection.topWidth(for: physicalAngle))
                    let geometricWidth = 1 - heightFromHinge * sin(theta) / 4
                    let visibleWidth = 1 - heightFromHinge * (1 - topWidth)
                    let panelX = ((Double(x) + 0.5) / Double(width) - 0.5) * geometricWidth / visibleWidth
                    let surface = SIMD3<Double>(panelX,
                                                heightFromHinge * cos(theta),
                                                heightFromHinge * sin(theta))
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
                        func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
                            let t = min(1, max(0, (value - low) / (high - low)))
                            return t * t * (3 - 2 * t)
                        }
                        let rawProgress = min(1, Double(amount) * 80 / (reference - 4))
                        let visibleProgress = rawProgress * rawProgress * (3 - 2 * rawProgress)
                        let darkness = pow(visibleProgress, 2.2)
                            * (1 - smoothstep(0.05, 1, 1 - heightFromHinge))
                        let degrees = Double(amount) * 80
                        let contactStrength = 0.88 * (1 - exp(-degrees / 3))
                        let contactDepth = 0.035 + 0.20 * (1 - exp(-degrees / 22))
                        let contactShadow = contactStrength * exp(-pow((1 - heightFromHinge) / contactDepth, 1.6))
                        expected *= (1 - darkness) * (1 - contactShadow)
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
        guard let highPixels = strengthPixels["frost40"],
              let regularPixels = strengthPixels["frostRegular40"],
              let subtlePixels = strengthPixels["frostSubtle40"],
              highPixels != regularPixels, regularPixels != subtlePixels else {
            throw failure("High, Regular, and Subtle must render distinct blur")
        }
        print("PASS: bounded GPU projection at 16°/40°/90°/120° and 45°/90° from one start angle, blur-off sharpness, three distinct blur strengths, orientation, opacity, retained-frame identity, top shadow, bottom-edge blur, frost at 20°/40°/52°/80°")
        try checkMaterial(renderer: renderer,
                          previewURL: outputURL.deletingLastPathComponent().appendingPathComponent("connection-glow.png"))
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
    /// Exercise the actual renderer timeline against uninterrupted lid tracking,
    /// so a separate easing path at the threshold cannot pass unnoticed.
    private static func checkManualCompletion(renderer: EffectRenderer) throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition {
                throw NSError(domain: "Glissform.RendererMotionTest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        let degree = Float(Double.pi / 180)
        for reclose in [false, true] {
            renderer.pauseSnapshot()
            renderer.foldRadians = 3 * degree
            renderer.renderedFold = 3 * degree
            renderer.smoothing.reset(to: 3 * degree, at: 0)
            renderer.lastDrawTime = 0
            var uninterrupted = renderer.smoothing
            for frame in 1...420 {
                let time = Double(frame) / 120
                if frame.isMultiple(of: 2) {
                    let angle = reclose && frame >= 204 ? 99 : 97 + Double(min(3, frame / 60))
                    renderer.setLidAngle(angle, referenceAngle: 100, sampleTime: time)
                    uninterrupted.ingest(target: ScreenProjection.foldRadians(lidAngle: angle, referenceAngle: 100), at: time)
                    if frame == 180 { renderer.finishAnimation(.lid) {} }
                    if reclose && frame == 204 { renderer.beginAnimation() }
                }
                renderer.advanceMotion(at: time)
                let expected = uninterrupted.step(at: time)
                try check(abs(renderer.renderedFold - expected) < 0.000001
                          && abs(renderer.renderedVelocity - uninterrupted.velocity) < 0.000001,
                          "The final degree and reclose must follow exactly the same lid trajectory")
                if expected > 0 {
                    try check(renderer.opacity == 1, "Manual completion cannot hide unfinished lid movement")
                }
                if frame == 179 {
                    try check(renderer.renderedFold >= degree && !renderer.ending,
                              "Holding one degree below the threshold must not start an automatic return")
                }
                if frame == 188 {
                    try check(renderer.renderedFold > 0.7 * degree,
                              "The last slow degree must not snap flat in four display frames")
                }
                if !reclose && frame == 276 {
                    try check(renderer.renderedFold > 0 && renderer.opacity == 1,
                              "Slow tracking may legitimately continue past an 800 ms finish deadline")
                }
            }
            try check(reclose ? (renderer.renderedFold == degree && renderer.opacity == 1 && !renderer.ending)
                      : (renderer.renderedFold == 0 && renderer.opacity == 0),
                      "Manual completion must either follow the reclosed lid or finish flat before fading")
        }
        print("PASS: final manual degree and reclose match uninterrupted lid tracking; fade waits for flat")

        for displayRate in [60.0, 120.0] {
            for quantized in [false, true] {
                for phase in [0.0, 0.004, 0.012] {
                    renderer.pauseSnapshot()
                    renderer.renderedFold = 20 * degree
                    renderer.smoothing.reset(to: 20 * degree, at: 0)
                    renderer.lastDrawTime = 0
                    var sample = 0
                    var requested = false
                    var entrySpeed = 0.0
                    var assist = OpeningAssist()
                    var previousFold = 20 * degree
                    for frame in 0...Int(3 * displayRate) {
                        let time = Double(frame) / displayRate
                        var requestedThisFrame = false
                        while phase + Double(sample) / 30 <= time {
                            let acquired = phase + Double(sample) / 30
                            let raw = min(100, 80 + 10 * acquired + 50 * acquired * acquired)
                            let angle = quantized ? raw.rounded(.down) : raw
                            renderer.foldRadians = Float((100 - angle) * .pi / 180)
                            renderer.smoothing.ingest(target: renderer.foldRadians, at: acquired)
                            if !requested, let speed = assist.observe(angle: angle, time: acquired,
                                                                     referenceAngle: 100, active: true) {
                                renderer.finishAnimation(.assisted, openingSpeed: speed) {}
                                requested = true
                                requestedThisFrame = true
                            }
                            sample += 1
                        }
                        var uninterrupted = renderer.smoothing
                        let manualFold = uninterrupted.step(at: time)
                        renderer.advanceMotion(at: time)
                        if requestedThisFrame {
                            try check(renderer.renderedFold == manualFold
                                      && renderer.renderedVelocity == uninterrupted.velocity,
                                      "An accelerating takeover must draw the newest lid frame before continuing")
                            entrySpeed = -renderer.renderedVelocity
                        } else if requested {
                            try check(renderer.renderedFold >= 0 && renderer.renderedFold <= previousFold,
                                      "A renderer handoff replay must finish without overshoot")
                            if renderer.renderedFold > 1.5 * degree {
                                try check(-renderer.renderedVelocity >= 0.95 * entrySpeed,
                                          "An accelerating renderer handoff must not brake toward a lagging estimate")
                            }
                            if renderer.renderedFold == 0 { break }
                        }
                        previousFold = renderer.renderedFold
                    }
                    try check(requested && renderer.renderedFold == 0,
                              "Each accelerating renderer replay must reach flat")
                }
            }
        }
        print("PASS: accelerated 60/120 Hz renderer handoff preserves the newest lid frame and opening momentum")

        func assistedFold(visibleSpeed: Double, measuredSpeed: Double, after duration: Double) throws -> Float {
            renderer.pauseSnapshot()
            renderer.renderedFold = Float(10 + visibleSpeed * 0.5) * degree
            renderer.smoothing.reset(to: renderer.renderedFold, at: -0.5)
            renderer.lastDrawTime = -0.5
            for frame in 1...60 {
                let time = -0.5 + Double(frame) / 120
                renderer.foldRadians = Float(10 - visibleSpeed * time) * degree
                renderer.smoothing.ingest(target: renderer.foldRadians, at: time)
                renderer.advanceMotion(at: time)
            }
            let entryVelocity = renderer.renderedVelocity
            var uninterrupted = renderer.smoothing
            let nextManualFold = uninterrupted.step(at: 1.0 / 120)
            renderer.finishAnimation(.assisted, openingSpeed: measuredSpeed) {}
            try check(renderer.connectionGlowSpread == 0,
                      "The opening glow must begin at zero at the assist handoff")
            var previousGlow: Float = 0
            var reachedFlat = false
            var contactTime: Double?
            var peakIntensity = connectionGlowApproachIntensity
            try check(renderer.renderedVelocity == entryVelocity,
                      "Requesting an assist must keep the existing displayed velocity")
            for frame in 1...Int(duration * 120) {
                renderer.advanceMotion(at: Double(frame) / 120)
                let frameSpeed = -renderer.renderedVelocity
                if !reachedFlat {
                    try check(renderer.connectionGlowSpread + 0.000001 >= previousGlow,
                              "The connection rim must spread inward during assisted opening")
                    if renderer.renderedFold == 0 {
                        try check(renderer.connectionGlowSpread == connectionGlowMaximumSpread,
                                  "The connection rim must reach its full width at flat")
                        contactTime = Double(frame) / 120
                        reachedFlat = true
                    } else {
                        try check(renderer.connectionGlowIntensity >= 1
                                  && renderer.connectionGlowIntensity < connectionGlowContactIntensity
                                  && !renderer.connectionGlowPulsing,
                                  "Anticipation may build before flat, but the brightness peak must follow contact")
                    }
                } else {
                    try check(renderer.connectionGlowSpread <= previousGlow + 0.000001,
                              "The connection rim must retreat outward after the image reaches flat")
                }
                previousGlow = renderer.connectionGlowSpread
                peakIntensity = max(peakIntensity, renderer.connectionGlowIntensity)
                if let contactTime, Double(frame) / 120 > contactTime + 0.22 {
                    try check(renderer.connectionGlowIntensity == connectionGlowApproachIntensity,
                              "The contact pulse must settle back before the spatial retreat finishes")
                }
                try check(frameSpeed >= 0
                          && frameSpeed <= 1.25 * max(measuredSpeed * Double(degree),
                                                     -uninterrupted.velocity, -entryVelocity) + 0.000001,
                          "Carried acceleration must stay within its bounded momentum allowance")
                if frame == 1 {
                    try check(renderer.renderedFold == nextManualFold
                              && renderer.renderedVelocity == uninterrupted.velocity,
                              "The first assisted frame must match continued lid tracking exactly")
                }
            }
            if duration >= 0.65 {
                try check(reachedFlat && renderer.opacity == 0 && renderer.connectionGlowSpread == 0,
                          "The desktop fade and rim retreat must both complete")
                try check(peakIntensity > 1.7,
                          "A completed connection must produce a brief intense light pulse")
            }
            return renderer.renderedFold
        }
        let fastOpening = try assistedFold(visibleSpeed: 20, measuredSpeed: 80, after: 0.1)
        let slowOpening = try assistedFold(visibleSpeed: 20, measuredSpeed: 10, after: 0.1)
        try check(fastOpening >= 0 && fastOpening < slowOpening && slowOpening < 10 * degree,
                  "Assisted opening must use measured hand speed, not the slower displayed speed")
        _ = try assistedFold(visibleSpeed: 20, measuredSpeed: 80, after: 0.65)
        _ = try assistedFold(visibleSpeed: 20, measuredSpeed: 40, after: 0.05)
        let beforeReversal = renderer.renderedFold
        let glowBeforeReversal = renderer.connectionGlowSpread
        try check(glowBeforeReversal > 0, "The assisted opening must show a growing glow before reversal")
        renderer.beginAnimation()
        try check(renderer.connectionGlowSpread == glowBeforeReversal,
                  "Reversal must not snap the opening glow away")
        renderer.setLidAngle(75, referenceAngle: 90, sampleTime: 0.06)
        for frame in 8...48 { renderer.advanceMotion(at: Double(frame) / 120) }
        try check(!renderer.ending && renderer.opacity == 1
                  && renderer.renderedFold > beforeReversal,
                  "A reversal during assisted opening must rejoin the captured image")
        try check(renderer.connectionGlowSpread == 0,
                  "The opening glow must release smoothly after reversal")
        try check(!renderer.connectionGlowPulsing
                  && renderer.connectionGlowIntensity == connectionGlowApproachIntensity,
                  "A pre-contact reversal must never produce a connection pulse")
        _ = try assistedFold(visibleSpeed: 20, measuredSpeed: 80, after: 0.1)
        var pulseFrame = 12
        while pulseFrame < 120 && renderer.connectionGlowIntensity == connectionGlowApproachIntensity {
            pulseFrame += 1
            renderer.advanceMotion(at: Double(pulseFrame) / 120)
        }
        try check(renderer.connectionGlowIntensity > connectionGlowApproachIntensity,
                  "The contact pulse must be visible before checking its interruption")
        renderer.beginAnimation()
        renderer.setLidAngle(75, referenceAngle: 90, sampleTime: Double(pulseFrame + 1) / 120)
        var previousIntensity = renderer.connectionGlowIntensity
        for frame in (pulseFrame + 1)...(pulseFrame + 48) {
            renderer.advanceMotion(at: Double(frame) / 120)
            try check(renderer.connectionGlowIntensity <= previousIntensity + 0.000001
                      && !renderer.connectionGlowPulsing,
                      "Reversing during contact must cancel the pulse without another rise")
            previousIntensity = renderer.connectionGlowIntensity
        }
        try check(renderer.connectionGlowIntensity == connectionGlowApproachIntensity
                  && renderer.connectionGlowSpread == 0,
                  "An interrupted contact pulse must settle and retreat completely")
        print("PASS: assisted opening blends into measured lid speed and rejoins the same image on reversal")

        for fold in [2.0, 5.0, 80.0, 120.0] {
            renderer.pauseSnapshot()
            renderer.renderedFold = Float(fold) * degree
            renderer.foldRadians = renderer.renderedFold
            renderer.smoothing.reset(to: renderer.renderedFold, at: 0)
            renderer.lastDrawTime = 0
            renderer.finishAnimation(.pause) {}
            var previousSpread: Float = 0
            var contactTime: Double?
            var peakIntensity: Float = 1
            var desktopVisibleDuringRetreat = false
            var glowVisibleBeforeContact = false
            for frame in 1...180 {
                let time = Double(frame) / 120
                renderer.advanceMotion(at: time)
                if contactTime == nil {
                    if renderer.renderedFold >= 5 * degree {
                        try check(renderer.connectionGlowSpread == 0,
                                  "Pause/Escape glow must stay hidden outside the final five visible degrees")
                    } else if renderer.renderedFold > 0 && renderer.connectionGlowSpread > 0 {
                        glowVisibleBeforeContact = true
                    }
                    try check(renderer.connectionGlowSpread >= previousSpread,
                              "Pause and Escape must gather the same rim inward during the final five degrees")
                    try check(renderer.connectionGlowIntensity >= connectionGlowApproachIntensity
                              && renderer.connectionGlowIntensity < connectionGlowContactIntensity,
                              "Pause and Escape may anticipate the click without peaking before contact")
                    if renderer.renderedFold == 0 {
                        contactTime = time
                        try check(renderer.connectionGlowPulsing
                                  && renderer.connectionGlowSpread == connectionGlowMaximumSpread,
                                  "Pause and Escape must begin the contact pulse only once the image is flat")
                    }
                } else {
                    try check(renderer.connectionGlowSpread <= previousSpread,
                              "Pause and Escape must retract the rim outward after contact")
                    if renderer.opacity == 0 && renderer.connectionGlowSpread > 0 {
                        desktopVisibleDuringRetreat = true
                    }
                }
                previousSpread = renderer.connectionGlowSpread
                peakIntensity = max(peakIntensity, renderer.connectionGlowIntensity)
            }
            try check(contactTime != nil && contactTime! <= 0.61
                      && glowVisibleBeforeContact && peakIntensity > 1.7 && desktopVisibleDuringRetreat
                      && renderer.opacity == 0 && renderer.connectionGlowSpread == 0,
                      "Pause and Escape must keep their return timing, click-aligned peak and 320 ms fading release")
        }
        do {
            renderer.pauseSnapshot()
            renderer.lastDrawTime = 0
            renderer.finishAnimation(.disabled) {}
            renderer.advanceMotion(at: 1)
            try check(renderer.connectionGlowSpread == 0 && !renderer.connectionGlowPulsing,
                      "Disabling must not gain connection feedback")
        }
        for fps in [60.0, 120.0] {
            for fold in [0.0, 2.0, 20.0] {
                renderer.pauseSnapshot()
                renderer.frameRate = Float(fps)
                renderer.renderedFold = Float(fold) * degree
                renderer.foldRadians = renderer.renderedFold
                renderer.smoothing.reset(to: renderer.renderedFold, at: 0)
                renderer.lastDrawTime = 0
                renderer.setLidAngle(100, referenceAngle: 100, sampleTime: 1 / fps)
                var uninterrupted = renderer.smoothing
                var schedules = 0
                var scheduledAt: Double?
                var requestedPeak: Double?
                var contactTime: Double?
                var identityTime: Double?
                var glowBeforeContact = false
                var peakIntensity: Float = 1
                renderer.finishAnimation(.lid, onConnectionSchedule: { peak, reply in
                    schedules += 1
                    scheduledAt = renderer.lastDrawTime
                    requestedPeak = peak
                    reply(peak)
                }) {}
                for frame in 1...Int(fps * 2) {
                    let time = Double(frame) / fps
                    let expectedFold = uninterrupted.step(at: time)
                    renderer.advanceMotion(at: time)
                    try check(renderer.renderedFold == expectedFold
                              && renderer.renderedVelocity == uninterrupted.velocity,
                              "Fast-opening feedback must preserve every frame of the existing lid smoothing")
                    if renderer.renderedFold >= 5 * degree {
                        try check(renderer.connectionGlowSpread == 0,
                                  "Fast-opening glow must stay hidden outside the final five visible degrees")
                    }
                    if renderer.renderedFold > Self.lidConnectionFold {
                        try check(!renderer.connectionGlowPulsing,
                                  "Fast-opening feedback must not pulse before visible contact")
                        glowBeforeContact = glowBeforeContact || renderer.connectionGlowSpread > 0
                    } else if contactTime == nil {
                        contactTime = time
                    }
                    if renderer.renderedFold == 0 && identityTime == nil { identityTime = time }
                    peakIntensity = max(peakIntensity, renderer.connectionGlowIntensity)
                }
                try check(contactTime != nil && identityTime != nil && scheduledAt != nil && requestedPeak != nil
                          && (fold == 0 || glowBeforeContact) && schedules == 1
                          && peakIntensity > 1.7 && renderer.opacity == 0 && renderer.connectionGlowSpread == 0,
                          "Fast opening must gather, pulse once at contact, fade and release at 60/120 Hz")
                try check(abs(requestedPeak! - contactTime! - ConnectionFeedbackTiming.attack) <= 1 / fps,
                          "Fast-opening feedback must target visible contact, not the invisible settling tail")
                if fold > 0 {
                    try check(scheduledAt! < contactTime! && contactTime! < identityTime!,
                              "Fast opening must queue audio ahead of visible contact while preserving the remaining motion")
                }
            }
        }
        print("PASS: skipped-angle feedback queues ahead of visible contact without changing the smoothing tail")
        for mode in [CompletionMode.lid, .pause, .assisted] {
            var motion: [[Float]] = []
            for enabled in [true, false] {
                renderer.pauseSnapshot()
                renderer.connectionEffectEnabled = enabled
                renderer.renderedFold = 4 * degree
                renderer.foldRadians = renderer.renderedFold
                renderer.smoothing.reset(to: renderer.renderedFold, at: 0)
                renderer.lastDrawTime = 0
                var schedules = 0
                renderer.finishAnimation(mode, openingSpeed: 30,
                    onConnectionSchedule: { peak, reply in schedules += 1; reply(peak) }) {}
                if mode == .lid {
                    renderer.setLidAngle(100, referenceAngle: 100, sampleTime: 0)
                }
                var frames: [Float] = []
                for frame in 1...120 {
                    renderer.advanceMotion(at: Double(frame) / 120)
                    frames += [renderer.renderedFold, Float(renderer.renderedVelocity), renderer.opacity]
                    if !enabled {
                        try check(renderer.connectionGlowSpread == 0 && !renderer.connectionGlowPulsing,
                                  "Connection effect off must suppress glow throughout the return")
                    }
                }
                try check(schedules == (enabled ? 1 : 0),
                          "The shared switch must suppress sound scheduling as well as glow")
                motion.append(frames)
            }
            try check(motion[0] == motion[1],
                      "The connection switch must preserve return geometry and screenshot fade")
        }
        renderer.connectionEffectEnabled = true
        renderer.pauseSnapshot()
        renderer.renderedFold = 2 * degree
        renderer.lastDrawTime = 0
        var disabledReply: ((Double?) -> Void)?
        renderer.finishAnimation(.pause, onConnectionSchedule: { _, reply in disabledReply = reply }) {}
        renderer.advanceMotion(at: 0.01)
        renderer.connectionEffectEnabled = false
        renderer.connectionEffectEnabled = true
        disabledReply?(10)
        renderer.advanceMotion(at: 0.02)
        try check(renderer.connectionPeakTime == nil && renderer.connectionGlowSpread == 0,
                  "A late audio reply after disabling must not revive glow on immediate re-enable")
        print("PASS: one connection switch suppresses glow/audio without changing return motion")
        for fps in [60.0, 120.0] {
            for mode in [CompletionMode.lid, .pause, .assisted] {
                for latency in [0.0, 0.160, 0.300] {
                    for startup in [0.0, 0.520] {
                        renderer.pauseSnapshot()
                        renderer.frameRate = Float(fps)
                        renderer.renderedFold = 2 * degree
                        renderer.foldRadians = renderer.renderedFold
                        renderer.smoothing.reset(to: renderer.renderedFold, at: 0)
                        renderer.lastDrawTime = 0
                        var requestedPeak: Double?
                        var reply: ((Double?) -> Void)?
                        var audiblePeak: Double?
                        var scheduleCount = 0
                        renderer.finishAnimation(mode, openingSpeed: 100, onConnectionSchedule: { peak, completion in
                            requestedPeak = peak
                            reply = completion
                            scheduleCount += 1
                        }) {}
                        if mode == .lid {
                            renderer.setLidAngle(100, referenceAngle: 100, sampleTime: 0)
                        }
                        var brightest: Float = 0
                        var brightestTime = 0.0
                        var flatTime: Double?
                        for frame in 1...Int(fps * 2) {
                            let time = Double(frame) / fps
                            if time >= startup, let complete = reply, let requestedPeak {
                                let plan = ConnectionFeedbackTiming.playback(requestedPeak: requestedPeak,
                                    now: time, latency: latency, samplePeak: 116 / 44100.0)
                                audiblePeak = plan.audiblePeak
                                reply = nil
                                complete(plan.audiblePeak)
                            }
                            renderer.advanceMotion(at: time)
                            if renderer.renderedFold == 0 && flatTime == nil { flatTime = time }
                            if renderer.connectionGlowIntensity > brightest {
                                brightest = renderer.connectionGlowIntensity
                                brightestTime = time
                            }
                            if renderer.renderedFold > (mode == .lid ? Self.lidConnectionFold : 0) {
                                try check(renderer.connectionGlowIntensity < connectionGlowContactIntensity,
                                          "The anticipated bloom must not peak before visible contact")
                            }
                            if renderer.connectionSchedulePending
                                || time < (renderer.connectionPeakTime ?? time) - ConnectionFeedbackTiming.glowAttack {
                                try check(renderer.connectionGlowIntensity == connectionGlowApproachIntensity,
                                          "Anticipation must wait for audio readiness and its short lead-in window")
                            }
                        }
                        try check(scheduleCount == 1 && audiblePeak != nil && brightest > 1.7,
                                  "Each completed return must schedule exactly one audible peak and one visible pulse")
                        try check(abs(brightestTime - audiblePeak!) <= 1 / fps,
                                  "Audio and glow peaks must agree within one display frame, including cold Bluetooth output")
                        try check(flatTime != nil && flatTime! < 0.42 && renderer.opacity == 0
                                  && renderer.connectionGlowSpread == 0,
                                  "Audio readiness must not delay geometry, desktop access or eventual glow cleanup")
                    }
                }
            }
        }
        renderer.pauseSnapshot()
        renderer.lastDrawTime = 0
        renderer.renderedFold = 2 * degree
        var staleReply: ((Double?) -> Void)?
        renderer.finishAnimation(.pause, onConnectionSchedule: { _, reply in staleReply = reply }) {}
        renderer.advanceMotion(at: 0.01)
        renderer.beginAnimation()
        staleReply?(10)
        try check(renderer.connectionPeakTime == nil && !renderer.connectionSchedulePending,
                  "An audio startup reply after reversal must not resurrect the canceled pulse")
        print("PASS: audio and glow peaks share a display clock at 60/120 Hz with warm, delayed and canceled scheduling")
        print("PASS: Pause/Escape glow stays within the final five degrees, shares contact feedback and preserves return timing")
    }

    private static func checkMaterial(renderer: EffectRenderer, previewURL: URL) throws {
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
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
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
        for degrees: Float in [1, 3, 6, 12, 24, 25, 40, 45, 60, 70] {
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
        renderer.connectionGlowSpread = connectionGlowMaximumSpread
        renderer.connectionGlowIntensity = connectionGlowApproachIntensity
        renderer.connectionGlowOpacity = 1
        let approachingGlow = try render(degrees: 0)
        renderer.connectionGlowIntensity = 1
        renderer.connectionGlowSpread = connectionGlowMaximumSpread / 3
        let gatheringGlow = try render(degrees: 0)
        renderer.connectionGlowSpread = connectionGlowMaximumSpread
        let connectedGlow = try render(degrees: 0)
        renderer.connectionGlowIntensity = connectionGlowContactIntensity
        let pulseGlow = try render(degrees: 0)
        renderer.connectionGlowIntensity = 1
        let halfImageGlow = try render(degrees: 0, opacity: 0.5)
        let liveDesktopGlow = try render(degrees: 0, opacity: 0)
        renderer.connectionGlowSpread = connectionGlowMaximumSpread / 1000
        let subpixelGlow = try render(degrees: 0, opacity: 0)
        renderer.connectionGlowSpread = 0
        let clearedGlow = try render(degrees: 0, opacity: 0)
        for (x, y) in [(0, height / 2), (width - 1, height / 2),
                       (width / 2, 0), (width / 2, height - 1)] {
            let offset = (y * width + x) * 4
            guard identity[offset] < gatheringGlow[offset],
                  gatheringGlow[offset] <= connectedGlow[offset],
                  abs(Int(connectedGlow[offset]) - Int(connectedGlow[offset + 1])) <= 1,
                  abs(Int(connectedGlow[offset + 1]) - Int(connectedGlow[offset + 2])) <= 1 else {
                throw failure("White connection glow must grow evenly from every screen edge")
            }
            let halfComposite = Int(halfImageGlow[offset])
                + Int((Float(255 - Int(halfImageGlow[offset + 3])) * 64 / 255).rounded())
            let liveComposite = Int(liveDesktopGlow[offset])
                + Int((Float(255 - Int(liveDesktopGlow[offset + 3])) * 64 / 255).rounded())
            guard abs(Int(connectedGlow[offset]) - halfComposite) <= 2,
                  abs(Int(connectedGlow[offset]) - liveComposite) <= 2,
                  liveDesktopGlow[offset] == liveDesktopGlow[offset + 3] else {
                throw failure("Connection glow must keep its brightness through the desktop handoff")
            }
        }
        for x in [0, 1, 3, 6] {
            let narrowSample = (height / 2 * width + x) * 4
            let wideSample = (height / 2 * width + 3 * x + 1) * 4
            guard abs(Int(gatheringGlow[narrowSample]) - Int(connectedGlow[wideSample])) <= 1 else {
                throw failure("Changing rim width must preserve the light profile without an opacity fade")
            }
        }
        let center = (height / 2 * width + width / 2) * 4
        let nearEdge = (height / 2 * width + 2) * 4
        let softShoulder = (height / 2 * width + 10) * 4
        let beyondRim = (height / 2 * width + 96) * 4
        guard connectedGlow[center] == identity[center]
              && connectedGlow[nearEdge] < 160
              && connectedGlow[softShoulder] > identity[softShoulder] + 20
              && connectedGlow[softShoulder] > gatheringGlow[softShoulder]
              && connectedGlow[beyondRim] == identity[beyondRim]
              && connectedGlow[(height / 2 * width) * 4] < 150
              && pulseGlow[(height / 2 * width) * 4] < 190
              && approachingGlow == connectedGlow
              && pulseGlow[softShoulder] > connectedGlow[softShoulder] + 15
              && liveDesktopGlow[center + 3] == 0
              && subpixelGlow.allSatisfy({ $0 == 0 })
              && clearedGlow.allSatisfy({ $0 == 0 }) else {
            throw failure("The soft inner glow must remain visible and pulse at contact without a pure white outline")
        }
        // Each field is smooth across the corner diagonal; a nearest-edge
        // distance produces a visible slope change as the closest side flips.
        let cornerY = 10
        let diagonal = (cornerY * width + cornerY) * 4
        let beforeDiagonal = diagonal - 2 * 4
        let afterDiagonal = diagonal + 2 * 4
        let cornerCurvature = abs(2 * Int(connectedGlow[diagonal])
                                  - Int(connectedGlow[beforeDiagonal]) - Int(connectedGlow[afterDiagonal]))
        guard cornerCurvature <= 3,
              connectedGlow[diagonal] <= connectedGlow[(height / 2 * width) * 4] else {
            throw failure("The connection glow must merge smoothly at corners without a brighter hotspot")
        }
        let provider = CGDataProvider(data: Data(connectedGlow) as CFData)!
        let preview = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                                  CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        try NSBitmapImageRep(cgImage: preview).representation(using: .png, properties: [:])!.write(to: previewURL)
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
                let contactStrength = 0.88 * (1 - exp(-50.0 / 3))
                let contactDepth = 0.035 + 0.20 * (1 - exp(-50.0 / 22))
                let contactShadow = contactStrength * exp(-pow(uv / contactDepth, 1.6))
                let linear = source * (1 - darkness) * (1 - contactShadow)
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

    /// Rendered preview material; wallpaper tiles use owner-supplied source art.
    static func materialPreview(outputDirectory: URL, wallpaperOnly: Bool = false) throws {
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
        if wallpaperOnly {
            // The owner-supplied wallpaper is cropped once and kept as a small
            // source asset so all three bundled previews can be regenerated.
            let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Artwork/BlurPreviewWallpaper.png")
            guard let image = NSImage(contentsOf: sourceURL) else {
                throw NSError(domain: "Glissform.MaterialPreview", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "Missing blur preview wallpaper at \(sourceURL.path)"])
            }
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                       from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        } else {
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
        let symbols: [IconlySymbol] = [.copy, .shieldDone, .pause, .laptop, .lock, .memory]
        for index in 0..<7 {
            let x = 229 + index * 73
            card(NSRect(x: x, y: 38, width: 64, height: 54), colors[index], radius: 13)
            symbols[index].image.draw(in: NSRect(x: x + 15, y: 49, width: 34, height: 32))
        }
        }
        NSGraphicsContext.restoreGraphicsState()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        renderer.update(pixelBuffer: buffer)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = wallpaperOnly ? [.renderTarget, .shaderRead, .shaderWrite] : [.renderTarget]
        guard let target = renderer.device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "Glissform.MaterialPreview", code: 4)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        func writeFrame(degrees: Int, strength: BlurStrength, name: String) throws {
            renderer.blurStrength = strength
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
            if wallpaperOnly {
                let fraction = min(1, max(0, renderer.foldRadians / max(0.001, renderer.fullClosureRadians)))
                let visibleProgress = fraction * fraction * (3 - 2 * fraction)
                let finishingRadius = min(Float(height) * 0.008, 24)
                    * pow(visibleProgress, 0.7) * 0.8 * strength.scale(at: fraction)
                if finishingRadius >= 0.5 {
                    // Core Image's finishing pass has the opposite readback
                    // origin from direct Metal output; flip only its PNG rows.
                    let rowBytes = width * 4
                    for row in 0..<(height / 2) {
                        let opposite = height - 1 - row
                        for column in 0..<rowBytes {
                            pixels.swapAt(row * rowBytes + column, opposite * rowBytes + column)
                        }
                    }
                }
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: outputDirectory.appendingPathComponent(name))
        }
        if wallpaperOnly {
            for strength in BlurStrength.allCases {
                try writeFrame(degrees: 42, strength: strength, name: "blur-\(strength.rawValue).png")
            }
        } else {
            for degrees in [0, 12, 24, 40, 60] {
                try writeFrame(degrees: degrees, strength: .high, name: "fold-\(degrees).png")
            }
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
    float4 connectionEdgeGlow(float3 color, float opacity, float2 pixel, float4 glow, float glowOpacity) {
        if (glow.x <= 0.0f || glowOpacity <= 0.0f) return layerColor(color, opacity);
        // Only the soft inner glow remains; there is no bright line at the
        // bezel. All four edges share the same reach relative to the display.
        // Allow subpixel widths so the rim can move fully beyond the bezel.
        // A one-pixel minimum would make its first and last frame pop.
        float spread = max(0.0001f, glow.x * min(glow.y, glow.z));
        float2 edge = max(float2(0.0f), min(pixel, glow.yz - pixel)) / spread;
        // A smooth distance field joins adjacent edges into one pool of light.
        // Unlike adding four strips, it cannot overexpose their intersections.
        float distance = edge.x * edge.y * rsqrt(dot(edge, edge) + 0.000001f);
        if (distance >= 2.7f) return layerColor(color, opacity);
        float pulse = saturate((glow.w - 1.0f) / 0.75f);
        // The shoulder and diffuse crest open together at contact. Keeping
        // the crest in place makes this one bloom instead of a second wave.
        float shoulderDistance = distance / (0.42f + 0.12f * pulse);
        float shoulder = exp(-shoulderDistance * shoulderDistance);
        float spill = exp(-distance * distance)
                    * (1.0f - smoothstep(1.8f, 2.7f, distance));
        float crestDistance = (distance - 0.16f) / 0.38f;
        float crest = exp(-crestDistance * crestDistance);
        float halo = 0.24f * shoulder + (0.08f + 0.025f * pulse) * spill
                   + 0.11f * pulse * crest;
        // Transmittance keeps the layered bloom soft at every edge and blends
        // the corners without a seam or a hard white outline.
        float boostedHalo = glow.w <= 1.0f ? halo
            : 1.0f - pow(1.0f - saturate(halo), glow.w);
        float light = 0.985f * boostedHalo * saturate(glowOpacity);
        // Composite in encoded color so the halo retains the same apparent
        // brightness as the screenshot fades to the live desktop underneath.
        float3 encoded = select(color * 12.92f,
                                1.055f * pow(color, float3(1.0f / 2.4f)) - 0.055f,
                                color > 0.0031308f);
        float3 premultiplied = encoded * opacity * (1.0f - light) + light;
        float alpha = opacity * (1.0f - light) + light;
        float3 forAttachment = select(premultiplied / 12.92f,
                                      pow((premultiplied + 0.055f) / 1.055f, float3(2.4f)),
                                      premultiplied > 0.04045f);
        return float4(forAttachment, alpha);
    }
    fragment float4 hingeFragment(Vertex in [[stage_in]], texture2d<float> desktop [[texture(0)]],
                                   constant float4 &uniforms [[buffer(0)]], constant float &frost [[buffer(1)]],
                                   constant float2 &eye [[buffer(2)]], constant float &opacity [[buffer(3)]],
                                   constant float &ditherScale [[buffer(4)]],
                                   constant float2 &imageShape [[buffer(5)]],
                                   constant float4 &glow [[buffer(6)]],
                                   constant float &glowOpacity [[buffer(7)]]) {
        constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
        float theta = max(0.0f, uniforms.w);
        // Only the displayed angle controls effect strength; a raw sensor
        // threshold must never switch the shader on or off during a handoff.
        if (theta == 0.0f) {
            float3 flat = desktop.sample(sampling, in.uv, level(0)).rgb;
            return connectionEdgeGlow(flat, opacity, in.position.xy, glow, glowOpacity);
        }
        float heightFromHinge = 1.0f - in.uv.y;
        // Trace to the original image plane. Retain a positive image response
        // through the full fold while limiting late vertical enlargement.
        // Top width begins changing promptly while the vertical source
        // position follows a continuously bounded perspective response.
        // Width changes linearly through the screen height so the sides and
        // vertical lines stay straight.
        // Tracking, frost and shadow continue to use the physical angle.
        float eyeDistance = eye.x;
        float eyeHeight = eye.y;
        float imageAngle = imageShape.x;
        float depth = heightFromHinge * sin(imageAngle);
        float planeHeight = heightFromHinge * cos(imageAngle);
        float rayScale = eyeDistance / (eyeDistance - depth);
        float visibleWidth = 1.0f - heightFromHinge * (1.0f - imageShape.y);
        float2 uv = float2(0.5f + (in.uv.x - 0.5f) / visibleWidth,
                          1.0f - (eyeHeight + (planeHeight - eyeHeight) * rayScale));
        // Closing progressively diffuses the whole stretched image, including
        // the hinge. Add more diffusion toward the top, furthest from the plane.
        // Use displayed closure progress rather than sin(theta): blur must keep
        // increasing even when a gesture rotates past 90 degrees, and reverse
        // continuously on reopening. The prepared zero-angle frame stays sharp.
        float verticalBlur = smoothstep(0.0f, 1.0f, heightFromHinge);
        // Keep defocus moving through the late fold rather than approaching its
        // final strength around the middle of the gesture.
        float frostAmount = pow(uniforms.x, 0.7f);
        float radius = frostAmount * uniforms.z * mix(0.015f, 0.090f, verticalBlur)
                     * mix(0.70f, 0.80f, verticalBlur) * frost;
        // A Gaussian pyramid is prepared once per screenshot. Keep only one
        // quarter of the target variance in its mip level, then reconstruct the
        // rest with a wider 5x5 binomial kernel. Bright controls exposed cells
        // from the old coarser mip and nine-tap reconstruction. The pyramid
        // variance is (4^level - 1) / 3; the kernel variance is step squared.
        // Together they retain the previous total blur variance of radius²/3.
        float lod = 0.5f * log2(1.0f + 0.25f * radius * radius);
        float2 step = radius * 0.5f / max(uniforms.yz, float2(1));
        const float weights[] = {0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f};
        float3 color = float3(0);
        for (uint y = 0; y < 5; ++y) {
            for (uint x = 0; x < 5; ++x) {
                float2 offset = float2(float(x) - 2.0f, float(y) - 2.0f) * step;
                color += desktop.sample(sampling, uv + offset, level(lod)).rgb * weights[x] * weights[y];
            }
        }
        // With zero-addressed taps, each sample column crosses
        // the source edge separately and draws a visible parallel contour at
        // either side of the projected desktop. Treat the screenshot as one
        // soft rectangle instead: clamp its colors, then fade their coverage
        // continuously over approximately two blur sigmas at every edge.
        float2 feather = max(float2(radius * 1.154700538f) / max(uniforms.yz, float2(1)),
                             float2(0.5f) / max(uniforms.yz, float2(1)));
        float2 entering = smoothstep(-feather, feather, uv);
        float2 leaving = 1.0f - smoothstep(1.0f - feather, 1.0f + feather, uv);
        color *= entering.x * entering.y * leaving.x * leaving.y;
        // Broad closure shading stays gentle; a separate contact shadow is
        // anchored to the physical top bezel, independent of projected image UVs.
        // Drive its onset with actual displayed degrees, not eased full-gesture
        // progress, so the first few degrees already reveal the frame's depth.
        float broadShadow = pow(uniforms.x, 2.2f)
                          * (1.0f - smoothstep(0.05f, 1.0f, in.uv.y));
        float degrees = theta * 57.2957795f;
        float contactStrength = 0.88f * (1.0f - exp(-degrees / 3.0f));
        float contactDepth = 0.035f + 0.20f * (1.0f - exp(-degrees / 22.0f));
        float contactShadow = contactStrength * exp(-pow(in.uv.y / contactDepth, 1.6f));
        color *= (1.0f - broadShadow) * (1.0f - contactShadow);
        // A fixed ordered threshold spreads final 8-bit rounding across pixels.
        // Repeating the same 8x8 tile made each row favor a different shade,
        // which left horizontal bands in broad pale gradients. Rotate the tile's
        // row phase across neighboring columns so every 64-pixel span samples
        // all 64 thresholds on each row. Keep the pattern fixed on screen to
        // avoid temporal noise. Zero identity and black stay exact.
        uint2 position = uint2(in.position.xy);
        uint2 tile = position >> 3;
        uint2 local = (position + uint2((tile.x * 3u + tile.y * 5u) & 7u,
                                           (tile.x * 5u + tile.y * 3u) & 7u)) & 7u;
        uint rank = 0;
        for (uint bit = 0; bit < 3; ++bit) {
            rank |= (((local.x >> bit) ^ (local.y >> bit)) & 1u) << (5u - 2u * bit);
            rank |= ((local.y >> bit) & 1u) << (4u - 2u * bit);
        }
        // Scale in linear light by the sRGB transfer slope; the perturbation
        // remains below half an encoded code value.
        float noise = ((float(rank) + 0.5f) / 64.0f - 0.5f) * ditherScale / 255.0f;
        float3 slope = select(float3(1.0f / 12.92f),
                             (2.4f / 1.055f) * pow(color, float3(1.4f / 2.4f)), color > 0.0031308f);
        color = select(float3(0), clamp(color + noise * slope, 0.0f, 1.0f), color > 0);
        return connectionEdgeGlow(color, opacity, in.position.xy, glow, glowOpacity);
    }
    """
}
