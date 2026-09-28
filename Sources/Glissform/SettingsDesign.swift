import AppKit
import SwiftUI

/// Shared foundations for the settings UI. Values are macOS points, not pixels.
/// Illustration geometry and small optical offsets remain local to their components.
enum SettingsDesign {
    enum Spacing {
        static let detail: CGFloat = 4
        static let label: CGFloat = 8
        static let controls: CGFloat = 12
        static let cards: CGFloat = 12
        static let cardInset: CGFloat = 16
        static let featureInset: CGFloat = 12
        static let controlSectionInset: CGFloat = 24
        static let angleFieldInset: CGFloat = 7
        static let angleFieldTrailingInset: CGFloat = 4
        static let switchCardInsets = EdgeInsets(top: featureInset, leading: featureInset,
                                                 bottom: featureInset, trailing: 24)
        static let groups: CGFloat = 24
        static let sections: CGFloat = 18
        static let page: CGFloat = 24
        static let optical: CGFloat = 2
    }

    enum Typography {
        static let pageTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let aboutTitle = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let headlineTracking: CGFloat = -0.24
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        static let controlTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let action = Font.system(size: 12, weight: .medium)
        static let liveValue = Font.system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
        static let editableValue = Font.system(size: 17, weight: .medium, design: .rounded).monospacedDigit()
        static let angleUnit = Font.system(size: 17)
    }

    enum Radius {
        static let icon: CGFloat = 12
        static let card: CGFloat = 16
        static let control: CGFloat = 8
        static let angleField: CGFloat = 7
        static let small: CGFloat = 4
    }

    enum Palette {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let card = Color(nsColor: .controlBackgroundColor)
        static let cardBorder = Color.primary.opacity(0.065)
        static let field = Color.primary.opacity(0.045)
        static let focus = Color.accentColor.opacity(0.65)
        static let switchOff = Color(nsColor: .tertiaryLabelColor)
        static let feature = Color(red: 78 / 255, green: 103 / 255, blue: 216 / 255)
        static let neutralSidebar = Color.gray
        static let feedbackSidebar = Color(red: 182 / 255, green: 104 / 255, blue: 112 / 255)
        static let success = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        static let batterySidebar = Color(red: 55 / 255, green: 196 / 255, blue: 91 / 255)
        static let attention = Color(red: 1, green: 159 / 255, blue: 10 / 255)
        static let danger = Color(red: 1, green: 69 / 255, blue: 58 / 255)
        enum CardIconColor {
            case feature, automaticAngle, blur, success, attention, danger, neutral

            var tile: Color {
                switch self {
                case .feature: return Palette.feature
                case .automaticAngle: return Color(red: 0xAD / 255, green: 0x91 / 255, blue: 0xDC / 255)
                case .blur: return Color(red: 0x70 / 255, green: 0xB9 / 255, blue: 0xEE / 255)
                case .success: return Palette.success
                case .attention: return Palette.attention
                case .danger: return Palette.danger
                case .neutral: return Color.gray
                }
            }

            func symbol(in scheme: ColorScheme) -> Color {
                switch (self, scheme) {
                case (.feature, .light): return Color(red: 0x43 / 255, green: 0x5C / 255, blue: 0xCD / 255)
                case (.automaticAngle, .light): return Color(red: 0x86 / 255, green: 0x63 / 255, blue: 0xC7 / 255)
                case (.blur, .light): return Color(red: 0x3B / 255, green: 0x94 / 255, blue: 0xD0 / 255)
                case (.success, .light): return Color(red: 0x2A / 255, green: 0xB8 / 255, blue: 0x4D / 255)
                case (.attention, .light): return Color(red: 0xE0 / 255, green: 0x8C / 255, blue: 0x09 / 255)
                case (.danger, .light): return Color(red: 0xDF / 255, green: 0x38 / 255, blue: 0x35 / 255)
                case (.feature, _): return Color(red: 0x66 / 255, green: 0x7C / 255, blue: 0xE7 / 255)
                case (.automaticAngle, _): return Color(red: 0xC2 / 255, green: 0xA6 / 255, blue: 0xED / 255)
                case (.blur, _): return Color(red: 0x8C / 255, green: 0xCE / 255, blue: 0xFF / 255)
                case (.success, _): return Palette.success
                case (.attention, _): return Palette.attention
                case (.danger, _): return Palette.danger
                case (.neutral, _): return .secondary
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
        static let fieldHoverFill = 0.035
        static let fieldHoverBorder = 0.12
        static let previewHoverFill = 0.08
        static let previewPressedFill = 0.13
        static let previewPressedBorder = 0.20
        static let hoverDuration = 0.12
        static let pressedDuration = 0.08
        static let switchDuration = 0.16
    }

    enum Metrics {
        static let contentWidth: CGFloat = 544
        static let sidebarWidth: CGFloat = 204
        static let sidebarIconRadius: CGFloat = 8
        static let sidebarRowInset: CGFloat = 7
        static let sidebarRowRadius = sidebarIconRadius + sidebarRowInset
        static let windowWidth = sidebarWidth + contentWidth
        static let preferredHeight: CGFloat = 560
        static let arrowWidth: CGFloat = 20
        static let arrowHeight: CGFloat = 17
        static let angleChevronSize: CGFloat = 14
        static let angleNumberWidth: CGFloat = 31
        static let iconSize: CGFloat = 44
    }
}
