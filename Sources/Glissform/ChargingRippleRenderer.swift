import AppKit
import MetalKit

enum BatteryRippleStyle: Float {
    case connected = 0
    case lowBattery = 1
}

/// A procedural light sheet. This renderer never reads desktop pixels.
final class ChargingRippleRenderer: NSObject, MTKViewDelegate {
    static let duration = 2.15
    static let reducedMotionDuration = 0.75
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let inFlight = DispatchSemaphore(value: 2)
    private var startedAt = 0.0
    private var reducedMotion = false
    private var style: BatteryRippleStyle = .connected

    init?(device: MTLDevice?) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "chargingVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "chargingFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Charging Ripple renderer: %@", error.localizedDescription)
            return nil
        }
        super.init()
    }

    func start(in view: MTKView, style: BatteryRippleStyle, reducedMotion: Bool, framesPerSecond: Int) {
        self.reducedMotion = reducedMotion
        self.style = style
        startedAt = ProcessInfo.processInfo.systemUptime
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.preferredFramesPerSecond = max(60, framesPerSecond)
        view.enableSetNeedsDisplay = false
        view.delegate = self
        view.isPaused = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let duration = reducedMotion ? Self.reducedMotionDuration : Self.duration
        let progress = Float((ProcessInfo.processInfo.systemUptime - startedAt) / duration)
        encode(pass: pass, buffer: buffer, width: drawable.texture.width,
               height: drawable.texture.height, progress: progress,
               reducedMotion: reducedMotion, style: style)
        buffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        buffer.present(drawable)
        buffer.commit()
        if progress >= 1 { view.isPaused = true }
    }

    private func encode(pass: MTLRenderPassDescriptor, buffer: MTLCommandBuffer,
                        width: Int, height: Int, progress: Float, reducedMotion: Bool,
                        style: BatteryRippleStyle) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = SIMD4<Float>(Float(width), Float(height), progress, reducedMotion ? 1 : 0)
        var colorMode = style.rawValue
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&colorMode, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The same shader rendered offscreen for visual and alpha checks.
    func renderSample(width: Int, height: Int, progress: Float, reducedMotion: Bool = false,
                      style: BatteryRippleStyle = .connected) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        // Private textures work on both Apple and Intel GPUs. Read back through a
        // shared buffer; shared textures are not supported by every Metal family.
        let rowBytes = ((width * 4 + 255) / 256) * 256
        guard let texture = device.makeTexture(descriptor: descriptor),
              let readback = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let buffer = queue.makeCommandBuffer() else {
            throw NSError(domain: "ChargingRipple", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create sample target"])
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        encode(pass: pass, buffer: buffer, width: width, height: height,
               progress: progress, reducedMotion: reducedMotion, style: style)
        guard let blit = buffer.makeBlitCommandEncoder() else {
            throw NSError(domain: "ChargingRipple", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot read sample target"])
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: rowBytes,
                  destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        if let error = buffer.error { throw error }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            for row in 0..<height {
                memcpy(bytes.baseAddress!.advanced(by: row * width * 4),
                       readback.contents().advanced(by: row * rowBytes), width * 4)
            }
        }
        return pixels
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    vertex float4 chargingVertex(uint id [[vertex_id]]) {
        const float2 vertices[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        return float4(vertices[id], 0, 1);
    }

    float bell(float x, float width) { return exp(-x * x / (width * width)); }

    fragment float4 chargingFragment(float4 position [[position]], constant float4 &u [[buffer(0)]],
                                     constant float &colorMode [[buffer(1)]]) {
        float t = clamp(u.z, 0.0, 1.0);
        if (t <= 0.0 || t >= 1.0) return float4(0);
        // Coordinates in screen heights, with light arriving just below the corner.
        float2 p = float2(position.x, u.y - position.y) / u.y;
        p += float2(0.035, 0.035);
        float2 q = p * float2(0.87, 1.08);
        float radius = length(q);
        float angle = atan2(q.y, q.x);
        float envelope = smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(0.53, 1.0, t));

        if (u.w > 0.5) {
            // Static geometry and colour: accessibility mode only changes opacity.
            float glow = exp(-dot(q, q) / 0.115);
            float alpha = glow * envelope * 0.40;
            float3 glowColor = colorMode > 0.5 ? float3(1.0, 0.24, 0.30) : float3(0.10, 0.87, 0.51);
            return float4(glowColor * alpha, alpha);
        }

        float travel = (1.0 - exp(-3.1 * max(0.0, t - 0.025))) / (1.0 - exp(-3.1 * 0.975));
        float front = 0.025 + 1.43 * travel;
        // Broad angular folds give the edge an unfurling, uneven silhouette.
        float curl = sin(angle * 3.5 - t * 2.1) * 0.115
                   + sin(angle * 7.0 + t * 1.3) * 0.034;
        float distance = radius - front - curl * smoothstep(0.0, 0.25, travel);
        float directional = 0.66 + 0.34 * sin(angle * 2.0 + 0.3);
        float crestWidth = 0.0028 + 0.0032 * travel;
        float crest = bell(distance, crestWidth);
        float softCrest = bell(distance + 0.009, 0.031);
        float outerBloom = bell(distance, 0.135);

        // A translucent volume follows the wave, with silky internal caustic folds.
        float behind = -distance;
        float sheet = smoothstep(-0.01, 0.055, behind) * exp(-max(0.0, behind) / 0.23);
        float foldPhase = behind * 26.0 + sin(angle * 5.2 - t * 1.6) * 2.6
                        + sin(angle * 9.0 + t * 0.9) * 0.6;
        float caustic = pow(max(0.0, sin(foldPhase)), 18.0) * sheet;
        float foldBody = (0.5 + 0.5 * sin(foldPhase - 0.6)) * sheet;
        float rimLight = 0.20 + 0.80 * pow(0.5 + 0.5 * sin(angle * 5.8 - t * 2.6), 3.0);
        float innerLip = bell(distance + 0.045 + 0.025 * sin(angle * 6.0 - t * 2.0), 0.004);
        float innerGlow = bell(distance + 0.052 + 0.025 * sin(angle * 6.0 - t * 2.0), 0.026);
        float pool = exp(-dot(q, q) / (0.09 + 0.16 * travel))
                   * (1.0 - smoothstep(0.28, 0.85, t));
        float shimmer = 0.5 + 0.5 * sin(angle * 5.0 + behind * 9.0 - t * 2.1);
        float3 emerald = float3(0.015, 0.61, 0.31);
        float3 jade = float3(0.07, 0.91, 0.55);
        float3 mint = float3(0.76, 1.0, 0.83);
        float3 edgeColor = mix(mint, float3(0.27, 0.91, 0.95), smoothstep(0.70, 1.0, shimmer) * 0.52);
        if (colorMode > 0.5) {
            emerald = float3(0.74, 0.035, 0.08);
            jade = float3(1.0, 0.19, 0.16);
            mint = float3(1.0, 0.65, 0.55);
            edgeColor = mix(mint, float3(1.0, 0.38, 0.30), smoothstep(0.70, 1.0, shimmer) * 0.52);
        }

        float bodyWeight = sheet * 0.11 + foldBody * 0.16;
        float poolWeight = pool * 0.23;
        float glowWeight = outerBloom * 0.09 + innerGlow * 0.08;
        float causticWeight = caustic * 0.23;
        float edgeWeight = (crest * 0.71 + innerLip * 0.24) * rimLight + softCrest * 0.16;
        float total = bodyWeight + poolWeight + glowWeight + causticWeight + edgeWeight;
        float3 color = (emerald * bodyWeight + jade * (poolWeight + glowWeight)
                      + mint * causticWeight + edgeColor * edgeWeight) / max(total, 0.0001);
        // Stable, subpixel dither prevents visible contours in the transparent haze.
        float dither = fract(52.9829189 * fract(dot(position.xy, float2(0.06711056, 0.00583715)))) - 0.5;
        float alpha = clamp(total * envelope * directional, 0.0, 0.84);
        alpha = clamp(alpha + dither / 255.0 * smoothstep(0.0, 0.02, alpha), 0.0, 0.84);
        return float4(clamp(color, 0.0, 1.0) * alpha, alpha);
    }
    """
}

final class ChargingRippleView: MTKView {
    override var isOpaque: Bool { false }
}
