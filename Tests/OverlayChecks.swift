import AppKit

/// Run while another app is full screen to exercise cross-application Spaces.
/// Uses a small solid-colour panel, with no sensor or screenshot access.
@main
struct OverlayChecks {
    @MainActor
    static func check(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "Glissform.OverlayTest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    static func isOnScreen(_ window: NSWindow) -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }

    @MainActor
    static func run() async throws {
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }) ?? NSScreen.main else {
            throw NSError(domain: "Glissform.OverlayTest", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "An active display is required"])
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for policy: NSApplication.ActivationPolicy in [.regular, .accessory] {
            try check(NSApp.setActivationPolicy(policy), "Test activation policy must be available")
            let window = OverlayWindow(contentRect: NSRect(x: screen.frame.midX - 60,
                                                           y: screen.frame.midY - 40, width: 120, height: 80))
            defer { window.close() }
            window.backgroundColor = .systemBlue
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            window.ignoresMouseEvents = false
            window.alphaValue = 1
            window.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 300_000_000)
            try check(window.isOnActiveSpace && isOnScreen(window) && window.occlusionState.contains(.visible),
                      "Overlay must join the visible Space with activation policy \(policy.rawValue)")
            try check(!window.isKeyWindow && !window.isMainWindow &&
                      frontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      "Overlay must leave the foreground app and keyboard focus unchanged")
            window.orderOut(nil)
            try await Task.sleep(nanoseconds: 100_000_000)
            try check(!isOnScreen(window), "Dismissed overlay must leave the screen")
            print("PASS: overlay visibility, foreground preservation and dismissal with \(policy == .regular ? "settings open" : "background") activation")
        }
    }

    static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do {
                try await run()
                exit(0)
            } catch {
                fputs("Overlay check failed: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }
}
