import AppKit
import ScreenCaptureKit
import CoreMedia

/// One in-memory screenshot per gesture; never starts a recording stream.
final class DesktopCapture {
    @MainActor func screenshot(displayID: CGDirectDisplayID) async throws -> CVPixelBuffer {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Glissform", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in display unavailable"])
        }
        // Failing closed is safer than capturing our own overlay recursively.
        guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw NSError(domain: "Glissform", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capture exclusion is not ready"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        let config = SCStreamConfiguration()
        // Match the live desktop at the handoff, before any frosting appears.
        config.width = Int(CGDisplayPixelsWide(displayID))
        config.height = Int(CGDisplayPixelsHigh(displayID))
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        try Task.checkCancellation()
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
        guard sample.isValid, let buffer = sample.imageBuffer else {
            throw NSError(domain: "Glissform", code: 3, userInfo: [NSLocalizedDescriptionKey: "Screenshot pixels unavailable"])
        }
        return buffer
    }
}
