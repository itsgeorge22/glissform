import AppKit
import MetalKit

@main
struct ChargingRippleRenderChecks {
    static func main() throws {
        guard let renderer = ChargingRippleRenderer(device: MTLCreateSystemDefaultDevice()) else {
            throw failure("Metal renderer unavailable")
        }
        let width = 960, height = 622
        let output = URL(fileURLWithPath: "build/charging-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for reduced in [false, true] {
            for t: Float in [0, 1, 1.1] {
                let pixels = try renderer.renderSample(width: width, height: height, progress: t, reducedMotion: reduced)
                guard pixels.allSatisfy({ $0 == 0 }) else { throw failure("Animation endpoints must be transparent") }
            }
        }
        for t: Float in [0.12, 0.28, 0.50, 0.76] {
            let pixels = try renderer.renderSample(width: width, height: height, progress: t)
            var maximumAlpha: UInt8 = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = pixels[i + 3]
                maximumAlpha = max(maximumAlpha, alpha)
                guard pixels[i] <= alpha, pixels[i + 1] <= alpha, pixels[i + 2] <= alpha else {
                    throw failure("Transparent output must use premultiplied colour")
                }
            }
            guard maximumAlpha > 10 && maximumAlpha < 230 else { throw failure("Light wave must stay visible and translucent") }
            guard let image = image(pixels, width: width, height: height) else { throw failure("Cannot decode sample") }
            for dark in [false, true] {
                let preview = try composite(image, width: width, height: height, dark: dark)
                let name = "\(dark ? "dark" : "light")-\(Int((t * 100).rounded())).png"
                try preview.write(to: output.appendingPathComponent(name))
            }
        }
        let early = try renderer.renderSample(width: width, height: height, progress: 0.12)
        let cornerAlpha = early[((height - 12) * width + 12) * 4 + 3]
        let oppositeAlpha = early[(12 * width + width - 12) * 4 + 3]
        guard cornerAlpha > 10 && oppositeAlpha == 0 else { throw failure("Light must originate in the lower-left corner") }
        // Reduced Motion keeps its spatial pattern fixed; only the fade changes.
        let reducedA = try renderer.renderSample(width: width, height: height, progress: 0.20, reducedMotion: true)
        let reducedB = try renderer.renderSample(width: width, height: height, progress: 0.40, reducedMotion: true)
        guard reducedA == reducedB else { throw failure("Reduced Motion must not move geometry or colour") }
        let red = try renderer.renderSample(width: width, height: height, progress: 0.28, style: .lowBattery)
        let green = try renderer.renderSample(width: width, height: height, progress: 0.28, style: .connected)
        var redDominant = false
        for i in stride(from: 0, to: red.count, by: 4) where red[i + 3] > 40 {
            guard red[i + 3] == green[i + 3] else { throw failure("Both colors must share ripple geometry") }
            guard red[i] <= red[i + 3], red[i + 1] <= red[i + 3], red[i + 2] <= red[i + 3] else {
                throw failure("Red ripple must remain premultiplied")
            }
            if Int(red[i + 2]) > Int(red[i + 1]) * 2 { redDominant = true }
        }
        guard redDominant else { throw failure("Low-battery ripple must be red") }
        if let redImage = image(red, width: width, height: height) {
            try composite(redImage, width: width, height: height, dark: false)
                .write(to: output.appendingPathComponent("low-battery-light-28.png"))
        }
        print("PASS: battery ripple colors, shared geometry, transparent endpoints, premultiplied alpha, corner origin and static Reduce Motion")
        print("Charging visual samples: \(output.path)")
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func composite(_ overlay: CGImage, width: Int, height: Int, dark: Bool) throws -> Data {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Cannot make preview") }
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
        context.setFillColor(dark ? color(0.065, 0.075, 0.11) : color(0.90, 0.92, 0.95))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // A synthetic content surface makes transparency legible without a screenshot.
        context.setFillColor(dark ? color(0.12, 0.14, 0.18) : color(0.985, 0.985, 0.99))
        let window = CGRect(x: 100, y: 85, width: 750, height: 450)
        context.addPath(CGPath(roundedRect: window, cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.fillPath()
        context.setFillColor(dark ? color(0.20, 0.23, 0.27) : color(0.82, 0.84, 0.87))
        for line in 0..<9 {
            context.fill(CGRect(x: 138, y: 145 + line * 34, width: line % 3 == 0 ? 450 : 620, height: 8))
        }
        context.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode preview")
        }
        return png
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "ChargingRippleChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
