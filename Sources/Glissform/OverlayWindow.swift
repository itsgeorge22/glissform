import AppKit

/// A system overlay that can accompany another app in its full-screen Space,
/// independently of whether Glissform's settings have a Dock entry.
final class OverlayWindow: NSPanel {
    private static let parkedBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    private static let visibleBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        canBecomeVisibleWithoutLogin = false
        isFloatingPanel = true
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = Self.parkedBehavior
        animationBehavior = .none
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A hidden overlay waits in every Space. Once it contains desktop pixels,
    /// keep it in the Space where the gesture began so Mission Control cannot
    /// duplicate that frozen image onto both sides of a Space transition.
    func pinToCurrentSpace() {
        collectionBehavior = Self.visibleBehavior
    }

    func parkAcrossSpaces() {
        collectionBehavior = Self.parkedBehavior
    }
}
