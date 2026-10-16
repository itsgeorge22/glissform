import AppKit

struct InstallerLayout: Decodable {
    let width: Int
    let height: Int
    let iconSize: Int
    let textSize: Int
    let iconLocations: [String: [Int]]
    let title: String
    let subtitle: String
    let arrowOpacity: Double
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: render-dmg-background.swift <layout.json> <starfield.png> <output-directory>\n", stderr)
    exit(1)
}
let layout = try JSONDecoder().decode(InstallerLayout.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
guard let wallpaper = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    fputs("Could not load installer wallpaper.\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = NSSize(width: layout.width, height: layout.height)

func centeredText(_ text: String, y: CGFloat, height: CGFloat, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: tracking
    ]
    NSAttributedString(string: text, attributes: attributes)
        .draw(in: NSRect(x: 36, y: y, width: size.width - 72, height: height))
}

// Match the approved 720 × 400 preview. Finder supplies the actual draggable
// app/folder icons and their labels; only the background and guidance are baked in.
let artwork = NSImage(size: size, flipped: true) { _ in
    let scale = max(size.width / wallpaper.size.width, size.height / wallpaper.size.height)
    let drawSize = NSSize(width: wallpaper.size.width * scale, height: wallpaper.size.height * scale)
    wallpaper.draw(in: NSRect(x: (size.width - drawSize.width) / 2,
                             y: (size.height - drawSize.height) / 2,
                             width: drawSize.width, height: drawSize.height),
                   from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    centeredText(layout.title, y: 56, height: 35,
                 font: .systemFont(ofSize: 29, weight: .medium),
                 color: NSColor(srgbRed: 245/255, green: 248/255, blue: 1, alpha: 1), tracking: -0.7)
    centeredText(layout.subtitle, y: 99, height: 21,
                 font: .systemFont(ofSize: 14),
                 color: NSColor(srgbRed: 215/255, green: 227/255, blue: 247/255, alpha: 1))

    // Finder supplies black filenames; white capsules provide their contrast.
    NSColor.white.setFill()
    for (name, position) in layout.iconLocations {
        let textWidth = (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(layout.textSize))
        ]).width
        let width = ceil(textWidth) + 16
        let pill = NSRect(x: CGFloat(position[0]) - width / 2,
                          y: CGFloat(position[1] + layout.iconSize / 2 + 9),
                          width: width, height: 20)
        NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
    }

    let arrowWidth = size.width * 0.29
    let scaleFactor = arrowWidth / 195.75
    let centerY = CGFloat(layout.iconLocations["Glissform.app"]![1])
    let origin = NSPoint(x: (size.width - arrowWidth) / 2 - 2 * scaleFactor,
                         y: centerY - 21 * scaleFactor - 14 * scaleFactor)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: origin.x + x * scaleFactor, y: origin.y + y * scaleFactor)
    }
    let arrow = NSBezierPath()
    arrow.lineWidth = 5.25 * scaleFactor
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: point(9.25, 39))
    arrow.curve(to: point(187.781, 43), controlPoint1: point(66.344, 12), controlPoint2: point(126.156, 17))
    arrow.move(to: point(175.094, 20))
    arrow.line(to: point(188.688, 44))
    arrow.line(to: point(164.219, 48))
    NSColor.white.withAlphaComponent(layout.arrowOpacity).setStroke()
    arrow.stroke()
    return true
}

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: layout.width * scale, pixelsHigh: layout.height * scale,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create installer artwork bitmap")
    }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    artwork.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode installer artwork")
    }
    try png.write(to: output.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png"))
}
