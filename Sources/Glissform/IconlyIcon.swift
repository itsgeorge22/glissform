import AppKit
import SwiftUI

enum IconlyStyle: String, CaseIterable {
    case outline = "Outline"
    case bulk = "Bulk"
    case bold = "Bold"
    case custom = "Custom"

    static var current: IconlyStyle { IconlyAppearance.shared.style }
}

final class IconlyAppearance: ObservableObject {
    static let shared = IconlyAppearance()
    @Published var style: IconlyStyle = .bold
    private init() {}
}

/// Iconly Regular vectors, with Bold, Bulk, and Outline bundled locally.
/// See docs/ICONLY.md for provenance and asset licensing.
enum IconlySymbol: String, CaseIterable {
    case shieldDone, shieldInfo, pause, chevronUp, lock, copy, memory, laptop

    private static let images: [IconlyStyle: [IconlySymbol: NSImage]] = Dictionary(uniqueKeysWithValues: [IconlyStyle.outline, .bulk, .bold].map { style in
        (style, Dictionary(uniqueKeysWithValues: allCases.map { symbol in
            guard let url = AppResource.url(symbol.rawValue, extension: "svg", subdirectory: "Iconly/\(style.rawValue)"),
                  let image = NSImage(contentsOf: url), image.isValid else {
                preconditionFailure("Missing or invalid Iconly asset: \(style.rawValue)/\(symbol.rawValue)")
            }
            image.isTemplate = true
            return (symbol, image)
        }))
    })

    // Card-only Bulk variants retain source paths, with stronger secondary layers.
    private static let cardImages: [ColorScheme: [IconlySymbol: NSImage]] = Dictionary(
        uniqueKeysWithValues: [(ColorScheme.light, "Light"), (.dark, "Dark")].map { scheme, folder in
            (scheme, Dictionary(uniqueKeysWithValues: [IconlySymbol.pause, .shieldDone, .shieldInfo].map { symbol in
                guard let url = AppResource.url(symbol.rawValue, extension: "svg",
                                                subdirectory: "Iconly/CustomCards/\(folder)"),
                      let image = NSImage(contentsOf: url), image.isValid else {
                    preconditionFailure("Missing Custom card icon: \(folder)/\(symbol.rawValue)")
                }
                image.isTemplate = true
                return (symbol, image)
            }))
        })

    // Keep future product icon adjustments here; the three source sets stay intact.
    private var customStyle: IconlyStyle {
        switch self {
        case .chevronUp: return .bold
        default: return .bulk
        }
    }

    func image(for style: IconlyStyle, cardScheme: ColorScheme? = nil) -> NSImage {
        if style == .custom, let cardScheme, let image = Self.cardImages[cardScheme]?[self] {
            return image
        }
        return Self.images[style == .custom ? customStyle : style]![self]!
    }
    var image: NSImage { image(for: .current) }
}

struct IconlyIcon: View {
    @ObservedObject private var appearance = IconlyAppearance.shared
    @Environment(\.colorScheme) private var colorScheme
    let isCardIcon: Bool
    let symbol: IconlySymbol
    var size: CGFloat = 16
    var rotation: Double = 0

    init(_ symbol: IconlySymbol, size: CGFloat = 16, rotation: Double = 0, isCardIcon: Bool = false) {
        self.isCardIcon = isCardIcon
        self.symbol = symbol
        self.size = size
        self.rotation = rotation
    }

    var body: some View {
        Image(nsImage: symbol.image(for: appearance.style, cardScheme: isCardIcon ? colorScheme : nil))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
    }
}
