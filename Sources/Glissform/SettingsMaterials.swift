import AppKit
import SwiftUI

/// Standard window material lets navigation pick up the surrounding desktop.
/// The detail column remains opaque, so text and controls retain their contrast.
struct SettingsWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Keep AppKit's system cursor active throughout a SwiftUI control hover.
struct SettingsActionCursor: ViewModifier {
    var isActionEnabled: Bool?
    @Environment(\.isEnabled) private var isEnabled
    @State private var pushedForEnabled: Bool?

    private var actionEnabled: Bool { isActionEnabled ?? isEnabled }

    func body(content: Content) -> some View {
        content
            .overlay {
                if !actionEnabled {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in updateHover(phase, enabled: false) }
                }
            }
            .onContinuousHover { phase in
                if actionEnabled { updateHover(phase, enabled: true) }
            }
            .onChange(of: actionEnabled) { _, enabled in
                if pushedForEnabled != nil { applyCursor(enabled: enabled) }
            }
            .onDisappear { restoreCursor() }
    }

    private func updateHover(_ phase: HoverPhase, enabled: Bool) {
        switch phase {
        case .active: applyCursor(enabled: enabled)
        case .ended: restoreCursor()
        }
    }

    private func applyCursor(enabled: Bool) {
        let cursor = enabled ? NSCursor.pointingHand : NSCursor.operationNotAllowed
        if pushedForEnabled != enabled {
            if pushedForEnabled != nil { NSCursor.pop() }
            cursor.push()
            pushedForEnabled = enabled
        } else {
            cursor.set()
        }
    }

    private func restoreCursor() {
        guard pushedForEnabled != nil else { return }
        NSCursor.pop()
        pushedForEnabled = nil
    }
}

struct SettingsNavigationButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsNavigationButton(selected: selected, pressed: configuration.isPressed,
                                 label: configuration.label)
    }
}

private struct SettingsNavigationButton<Label: View>: View {
    let selected: Bool
    let pressed: Bool
    let label: Label
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: SettingsDesign.Metrics.sidebarRowRadius, style: .continuous)
                        .fill(.primary.opacity(pressed ? 0.13 : 0.10))
                } else {
                    RoundedRectangle(cornerRadius: SettingsDesign.Metrics.sidebarRowRadius)
                        .fill(.primary.opacity(pressed ? 0.10 : hovered ? 0.045 : 0))
                }
            }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}

struct SettingsDetailSurface: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: scheme == .dark
            ? [Color(white: 0.12), Color(white: 0.105)]
            : [Color(red: 0.985, green: 0.987, blue: 0.995), Color(red: 0.956, green: 0.961, blue: 0.978)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
