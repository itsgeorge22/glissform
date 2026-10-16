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
        static let angleFieldInset: CGFloat = 7
        static let angleFieldTrailingInset: CGFloat = 4
        static let mainCardInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 24)
        static let supportCardInsets = EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24)
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
        // Shared sRGB accents from the website's _colors.scss and _feature-palette.scss.
        // Keep app surfaces adaptive; website illustration backgrounds are separate.
        private static let primaryHex: UInt32 = 0x0073FF
        static let primaryBlue = srgb(primaryHex)
        static let primaryStrong = srgb(0x0068DF)
        static let primaryHover = srgb(primaryHex, shade: 0.10)
        static let primaryPressed = srgb(primaryHex, shade: 0.20)
        static let automaticAngle = srgb(0xA079DD)
        static let automaticAngleStrong = srgb(0x8653CC)
        static let blur = srgb(0x35B4AF)
        static let connectionEffect = srgb(0xF39A43)
        static let connectionStrong = srgb(0x96613C)
        static let success = srgb(0x30D158)
        // The existing permission symbol remains stronger on light app surfaces.
        static let successStrong = srgb(0x2AB84D)

        static let feature = primaryBlue
        static let generalSidebar = neutral
        static let aboutSidebar = srgb(0xED6258)
        static let feedbackSidebar = connectionEffect
        static let licenseSidebar = success
        static let externalDisplay = srgb(0xDB648A)
        static let pause = success
        static let attention = connectionEffect
        static let onAccent = Color.white
        static let iconTileOpacity = 0.12

        static let background = Color(nsColor: .windowBackgroundColor)
        static let card = Color(nsColor: .controlBackgroundColor)
        static let cardBorder = Color.primary.opacity(0.065)
        static let field = Color.primary.opacity(0.045)
        static let focus = primaryBlue.opacity(0.65)
        static let switchOff = Color(nsColor: .tertiaryLabelColor)
        static let neutral = Color.gray
        private static let detailLight = [Color(red: 0.985, green: 0.987, blue: 0.995),
                                          Color(red: 0.956, green: 0.961, blue: 0.978)]
        private static let detailDark = [Color(white: 0.12), Color(white: 0.105)]

        static func detailGradient(in scheme: ColorScheme) -> [Color] {
            scheme == .dark ? detailDark : detailLight
        }

        static func link(in scheme: ColorScheme) -> Color {
            scheme == .light ? primaryStrong : primaryBlue
        }

        // Shade in sRGB to match the website's color-mix(..., black 10% / 20%).
        private static func srgb(_ hex: UInt32, shade: Double = 0) -> Color {
            let scale = (1 - shade) / 255
            return Color(.sRGB, red: Double((hex >> 16) & 0xFF) * scale,
                         green: Double((hex >> 8) & 0xFF) * scale,
                         blue: Double(hex & 0xFF) * scale, opacity: 1)
        }
        enum CardIconColor {
            case feature, automaticAngle, connectionEffect, externalDisplay, blur, pause, feedback, success, attention, neutral

            var tile: Color {
                switch self {
                case .feature: return Palette.feature
                case .connectionEffect: return Palette.connectionEffect
                case .externalDisplay: return Palette.externalDisplay
                case .automaticAngle: return Palette.automaticAngle
                case .blur: return Palette.blur
                case .pause: return Palette.pause
                case .feedback: return Palette.feedbackSidebar
                case .success: return Palette.success
                case .attention: return Palette.attention
                case .neutral: return Palette.neutral
                }
            }

            func symbol(in scheme: ColorScheme) -> Color {
                switch (self, scheme) {
                case (.automaticAngle, .light): return Palette.automaticAngleStrong
                case (.pause, .light), (.success, .light): return Palette.successStrong
                case (.attention, .light): return Palette.connectionStrong
                case (.feature, _): return Palette.feature
                case (.connectionEffect, _): return Palette.connectionEffect
                case (.externalDisplay, _): return Palette.externalDisplay
                case (.automaticAngle, _): return Palette.automaticAngle
                case (.feedback, _): return Palette.feedbackSidebar
                case (.blur, _): return Palette.blur
                case (.pause, _): return Palette.pause
                case (.success, _): return Palette.success
                case (.attention, _): return Palette.attention
                case (.neutral, _): return Palette.neutral
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
