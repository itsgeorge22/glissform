import AppKit
import SwiftUI

/// Bundled feature artwork, independent of the developer Iconly style selector.
enum FeatureSymbol: String, CaseIterable {
    case batteryRipple = "empty-battery"
    case powerConnection = "charge-battery"
    case batteryAt20Percent = "low-battery"
    case infiniteScreen = "monitor-display"
    case automaticAngle = "scan-object"
    case blur = "rain-drop"
    case sendFeedback = "messages"
    case general = "setting"
    case backgroundRunning = "web-page-check"
    case menuBarIcon = "grid-interface"
    case launchAtLogin = "user"

    private static let images: [FeatureSymbol: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { symbol in
        guard let url = Bundle.module.url(forResource: symbol.rawValue, withExtension: "svg", subdirectory: "FeatureIcons"),
              let image = NSImage(contentsOf: url), image.isValid else {
            preconditionFailure("Missing or invalid feature icon: \(symbol.rawValue)")
        }
        image.isTemplate = true
        return (symbol, image)
    })

    var image: NSImage { Self.images[self]! }
}

struct FeatureIcon: View {
    let symbol: FeatureSymbol
    var size: CGFloat = 24

    init(_ symbol: FeatureSymbol, size: CGFloat = 24) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(nsImage: symbol.image)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
