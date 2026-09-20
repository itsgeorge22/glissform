import AppKit

/// A monochrome template derived from the actual Clear app icon.
enum BrandIcon {
    static let menuBar: NSImage = {
        guard let image = Bundle.main.image(forResource: "GlissformMenuBar"), image.isValid else {
            preconditionFailure("Missing GlissformMenuBar asset; build with scripts/build.sh")
        }
        image.size = NSSize(width: 18, height: 18)
        // macOS supplies the menu bar foreground color and highlighted appearance.
        image.isTemplate = true
        return image
    }()
}
