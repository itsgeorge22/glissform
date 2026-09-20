import AppKit
import CoreGraphics

enum DesktopAvailability {
    /// macOS has no public, general-purpose "desktop unlocked" notification.
    /// Combine public session/display checks with the optional system lock hint;
    /// the coordinator also cancels on distributed lock and session-switch events.
    /// These lock hints are undocumented and require physical OS-version testing.
    static func allowsCapture(displayID: CGDirectDisplayID) -> Bool {
        guard CGPreflightScreenCaptureAccess(), CGDisplayIsActive(displayID) != 0,
              CGDisplayIsAsleep(displayID) == 0,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true,
              let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated, let identifier = app.bundleIdentifier else { return false }
        return identifier != "com.apple.loginwindow" && identifier != "com.apple.ScreenSaver.Engine"
    }
}
