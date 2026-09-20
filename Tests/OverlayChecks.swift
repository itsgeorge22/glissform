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
        // Let Launch Services finish the standalone host's background launch
        // before testing a transition to regular activation. Its asynchronous
        // startup otherwise races the foreground-preservation assertion.
        try await Task.sleep(nanoseconds: 300_000_000)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        try check(CGDisplayIsAsleep(CGMainDisplayID()) == 0 &&
                  session?["CGSSessionScreenIsLocked"] as? Bool != true,
                  "Live overlay checks require an awake, unlocked desktop")
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
            try check(!window.canBecomeVisibleWithoutLogin, "Overlay must retain normal login visibility restrictions")
            window.backgroundColor = .systemBlue
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            window.ignoresMouseEvents = false
            window.alphaValue = 1
            window.orderFrontRegardless()
            // Space membership/occlusion updates arrive asynchronously after
            // an activation-policy change, especially after another UI test exits.
            for _ in 0..<100 {
                if window.isOnActiveSpace && isOnScreen(window) && window.occlusionState.contains(.visible) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try check(window.isOnActiveSpace && isOnScreen(window) && window.occlusionState.contains(.visible),
                      "Overlay must join the visible Space with activation policy \(policy.rawValue)")
            try check(!window.isKeyWindow && !window.isMainWindow &&
                      frontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      "Overlay must leave foreground and focus unchanged (before \(frontmost ?? -1), after \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1), self \(ProcessInfo.processInfo.processIdentifier), key \(window.isKeyWindow), main \(window.isMainWindow))")
            window.orderOut(nil)
            try await Task.sleep(nanoseconds: 100_000_000)
            try check(!isOnScreen(window), "Dismissed overlay must leave the screen")
            print("PASS: overlay visibility, foreground preservation and dismissal with \(policy == .regular ? "settings open" : "background") activation")
        }
    }

    static func main() {
        _ = NSApplication.shared
        // Complete the command-line test host's launch without foregrounding
        // it. Otherwise its delayed regular-app activation can race the panel
        // assertion, even when the production panel never takes focus.
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        Task { @MainActor in
            do {
                try await run()
                NSApp.setActivationPolicy(.accessory)
                NSApp.terminate(nil)
            } catch {
                fputs("Overlay check failed: \(error)\n", stderr)
                NSApp.setActivationPolicy(.accessory)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }
}
