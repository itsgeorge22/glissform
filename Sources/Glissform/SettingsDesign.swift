import AppKit
import SwiftUI

/// Shared foundations for the settings UI. Values are macOS points, not pixels.
/// Illustration geometry and small optical offsets remain local to their components.
enum SettingsDesign {
    enum Spacing {
        static let detail: CGFloat = 4
        static let label: CGFloat = 8
        static let controls: CGFloat = 12
        static let cards: CGFloat = 16
        static let cardInset: CGFloat = 20
        static let groups: CGFloat = 24
        static let sections: CGFloat = 28
        static let page: CGFloat = 32
        static let optical: CGFloat = 2
    }

    enum Typography {
        static let pageTitle = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let aboutTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let controlTitle = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let action = Font.system(size: 11, weight: .medium)
        static let liveValue = Font.system(size: 28, weight: .light, design: .rounded).monospacedDigit()
        static let editableValue = Font.system(size: 20, weight: .medium, design: .rounded).monospacedDigit()
        static let angleUnit = Font.system(size: 20)
    }

    enum Radius {
        static let card: CGFloat = 20
        static let icon: CGFloat = 12
        static let control: CGFloat = 8
        static let small: CGFloat = 4
    }

    enum Palette {
        static let background = Color(nsColor: .textBackgroundColor)
        static let card = Color.primary.opacity(0.035)
        static let cardBorder = Color.primary.opacity(0.04)
        static let dividerOverlay = Color.primary.opacity(0.025)
        static let field = Color.primary.opacity(0.045)
        static let focus = Color.accentColor.opacity(0.65)
        static let switchOff = Color(nsColor: .tertiaryLabelColor)
        static let feature = Color(red: 78 / 255, green: 103 / 255, blue: 216 / 255)
        static let success = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        static let sound = Color(red: 69 / 255, green: 203 / 255, blue: 234 / 255)
        static let attention = Color(red: 1, green: 159 / 255, blue: 10 / 255)
        static let iconTileOpacity = 0.16

        static func cardIcon(_ color: CardIconColor, scheme: ColorScheme) -> Color {
            let hex: UInt32
            switch (color, scheme) {
            case (.feature, .light): hex = 0x435CCD
            case (.success, .light): hex = 0x2AB84D
            case (.sound, .light): hex = 0x0784AA
            case (.attention, .light): hex = 0xE08C09
            case (.feature, _): hex = 0x667CE7
            case (.success, _): hex = 0x30D158
            case (.sound, _): hex = 0x61D8F4
            case (.attention, _): hex = 0xFF9F0A
            }
            return Color(red: Double((hex >> 16) & 255) / 255,
                         green: Double((hex >> 8) & 255) / 255,
                         blue: Double(hex & 255) / 255)
        }

        enum CardIconColor {
            case feature, success, sound, attention

            var tile: Color {
                switch self {
                case .feature: return Palette.feature
                case .success: return Palette.success
                case .sound: return Palette.sound
                case .attention: return Palette.attention
                }
            }
        }
    }

    enum Feedback {
        static let disabledOpacity = 0.45
        static let idleFill = 0.06
        static let hoverFill = 0.10
        static let pressedFill = 0.18
        static let hoverBorder = 0.18
        static let pressedBorder = 0.30
        static let hoverDuration = 0.12
        static let pressedDuration = 0.08
        static let switchDuration = 0.16
    }

    enum Metrics {
        static let windowWidth: CGFloat = 720
        static let preferredHeight: CGFloat = 780
        static let arrowWidth: CGFloat = 24
        static let arrowHeight: CGFloat = 20
        static let iconSize: CGFloat = 44
    }
}
