import AppKit

// Preserve the Clear rendition's original contours and wave as template opacity.
// Simply setting isTemplate on the opaque app tile would produce a solid square.
for path in CommandLine.arguments.dropFirst() {
    guard let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))),
          let mask = NSBitmapImageRep(bitmapDataPlanes: nil,
              pixelsWide: source.pixelsWide, pixelsHigh: source.pixelsHigh,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
              isPlanar: false, colorSpaceName: .deviceRGB,
              bitmapFormat: .alphaNonpremultiplied, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("Cannot load menu icon: \(path)") }
    guard let pixels = mask.bitmapData else { fatalError("Cannot allocate menu icon pixels") }
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide {
            guard let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                fatalError("Cannot read menu icon pixel")
            }
            let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
            let opacity = min(1, max(0, (luminance - 0.08) / 0.82)) * color.alphaComponent
            let offset = y * mask.bytesPerRow + x * 4
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = UInt8((opacity * 255).rounded())
        }
    }
    guard let data = mask.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode menu icon")
    }
    // Check the encoded PNG, not only the in-memory representation: a valid but
    // fully transparent image otherwise builds successfully and disappears in UI.
    guard let encoded = NSBitmapImageRep(data: data) else {
        fatalError("Cannot decode menu template")
    }
    var visiblePixels = 0
    for y in 0..<encoded.pixelsHigh {
        for x in 0..<encoded.pixelsWide {
            if (encoded.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.25 {
                visiblePixels += 1
            }
        }
    }
    guard visiblePixels > encoded.pixelsWide * encoded.pixelsHigh / 4 else {
        fatalError("Menu template is empty or too faint: \(path)")
    }
    try data.write(to: URL(fileURLWithPath: path))
}
