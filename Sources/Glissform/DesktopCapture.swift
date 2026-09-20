import AppKit
import ScreenCaptureKit
import CoreMedia

protocol DesktopScreenshotSource {
    @MainActor func prepare(displayID: CGDirectDisplayID, excludingWindowID: CGWindowID,
                            expectedPixelSize: CGSize) async throws
    @MainActor func invalidate()
    @MainActor func screenshot(displayID: CGDirectDisplayID) async throws -> CVPixelBuffer
}

extension DesktopScreenshotSource {
    // Synthetic sources do not have display metadata or an overlay to exclude.
    @MainActor func prepare(displayID: CGDirectDisplayID, excludingWindowID: CGWindowID,
                            expectedPixelSize: CGSize) async throws {}
    @MainActor func invalidate() {}
}

/// Capture dimensions are backing pixels, not the display's logical mode size.
struct CapturePixelSize: Equatable {
    let width: Int
    let height: Int

    init(contentRect: CGRect, pointPixelScale: CGFloat, expectedPixelSize: CGSize) throws {
        let width = contentRect.width * pointPixelScale
        let height = contentRect.height * pointPixelScale
        guard pointPixelScale.isFinite, pointPixelScale > 0,
              width.isFinite, height.isFinite, width >= 1, height >= 1,
              width < CGFloat(Int.max), height < CGFloat(Int.max),
              expectedPixelSize.width.isFinite, expectedPixelSize.height.isFinite,
              expectedPixelSize.width >= 1, expectedPixelSize.height >= 1,
              width.rounded() == expectedPixelSize.width.rounded(),
              height.rounded() == expectedPixelSize.height.rounded() else {
            throw CapturePreparationError.displaySizeChanged
        }
        self.width = Int(width.rounded())
        self.height = Int(height.rounded())
    }

    func matches(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferGetWidth(buffer) == width && CVPixelBufferGetHeight(buffer) == height
    }
}

enum CapturePreparationError: LocalizedError {
    case displayUnavailable, overlayUnavailable, displaySizeChanged, pixelsUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "Built-in display unavailable"
        case .overlayUnavailable: return "Capture exclusion is not ready"
        case .displaySizeChanged: return "Display pixel dimensions changed"
        case .pixelsUnavailable: return "Screenshot pixels unavailable"
        }
    }
}

struct CaptureWindowIdentity {
    let windowID: CGWindowID
    let ownerPID: pid_t?
}

/// A hidden alpha-zero overlay may be omitted from shareable-content metadata.
/// Application exclusion still protects it; only known, different own windows
/// are then included as explicit exceptions.
enum CaptureExclusionPlan: Equatable {
    case window(CGWindowID)
    case application(exceptingWindowIDs: [CGWindowID])

    static func make(excludingWindowID: CGWindowID, ownPID: pid_t,
                     applicationAvailable: Bool, windows: [CaptureWindowIdentity]) throws -> Self {
        guard excludingWindowID != 0 else { throw CapturePreparationError.overlayUnavailable }
        if let overlay = windows.first(where: { $0.windowID == excludingWindowID }) {
            guard overlay.ownerPID == ownPID else { throw CapturePreparationError.overlayUnavailable }
            return .window(excludingWindowID)
        }
        guard applicationAvailable else { throw CapturePreparationError.overlayUnavailable }
        let exceptions = windows.filter { $0.ownerPID == ownPID && $0.windowID != excludingWindowID }
            .map(\.windowID)
        return .application(exceptingWindowIDs: Array(Set(exceptions)).sorted())
    }
}

/// Shares metadata discovery between prewarming and a gesture without retaining pixels.
/// Invalidation prevents a late result from repopulating a newer display/session.
@MainActor final class CaptureMetadataCache<Value> {
    private var cached: (value: Value, time: TimeInterval)?
    private var pending: (task: Task<(value: Value, time: TimeInterval), Error>, generation: UInt64)?
    private var generation: UInt64 = 0
    private let lifetime: TimeInterval
    private let now: () -> TimeInterval

    init(lifetime: TimeInterval = 30,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.lifetime = lifetime
        self.now = now
    }

    func invalidate() {
        generation &+= 1
        pending?.task.cancel()
        pending = nil
        cached = nil
    }

    func value(load: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let cached, (0...lifetime).contains(now() - cached.time) { return cached.value }
        let operation: (task: Task<(value: Value, time: TimeInterval), Error>, generation: UInt64)
        if let pending { operation = pending }
        else {
            generation &+= 1
            let clock = now
            operation = (Task {
                let result = try await load()
                try Task.checkCancellation()
                return (result, clock())
            }, generation)
            pending = operation
        }
        do {
            let result = try await operation.task.value
            try Task.checkCancellation()
            guard generation == operation.generation else { throw CancellationError() }
            // A cancelled prewarm waiter may leave completed shared discovery
            // behind. Its lifetime begins at discovery, not at the next gesture.
            guard (0...lifetime).contains(now() - result.time) else {
                if pending?.generation == operation.generation { pending = nil }
                return try await value(load: load)
            }
            if pending?.generation == operation.generation {
                cached = result
                pending = nil
            }
            return result.value
        } catch {
            // Cancelling one waiter must not cancel discovery another waiter uses.
            if !Task.isCancelled, pending?.generation == operation.generation { pending = nil }
            throw error
        }
    }
}

/// One in-memory screenshot per gesture; never starts a recording stream.
@MainActor final class DesktopCapture: DesktopScreenshotSource {
    private struct Request: Equatable {
        let displayID: CGDirectDisplayID
        let excludedWindowID: CGWindowID
        let expectedPixelSize: CGSize
    }

    private struct PreparedCapture {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let pixelSize: CapturePixelSize
    }

    private var request: Request?
    private var generation: UInt64 = 0
    private let metadata = CaptureMetadataCache<PreparedCapture>()

    func invalidate() {
        generation &+= 1
        request = nil
        metadata.invalidate()
    }

    /// Prepares metadata only; screen pixels are requested solely by screenshot().
    func prepare(displayID: CGDirectDisplayID, excludingWindowID: CGWindowID,
                 expectedPixelSize: CGSize) async throws {
        let next = Request(displayID: displayID, excludedWindowID: excludingWindowID,
                           expectedPixelSize: expectedPixelSize)
        if request != next {
            invalidate()
            request = next
        }
        guard excludingWindowID != 0 else { throw CapturePreparationError.overlayUnavailable }
        let token = generation
        _ = try await metadata.value { try await Self.prepareMetadata(for: next) }
        guard token == generation, request == next else { throw CancellationError() }
    }

    private static func prepareMetadata(for request: Request) async throws -> PreparedCapture {
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw CapturePreparationError.displayUnavailable
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.first { $0.processID == ownPID }
        let plan = try CaptureExclusionPlan.make(excludingWindowID: request.excludedWindowID,
                                                 ownPID: ownPID, applicationAvailable: ownApp != nil,
                                                 windows: content.windows.map {
            CaptureWindowIdentity(windowID: $0.windowID, ownerPID: $0.owningApplication?.processID)
        })
        let filter: SCContentFilter
        switch plan {
        case .window(let windowID):
            guard let overlay = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CapturePreparationError.overlayUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [overlay])
        case .application(let windowIDs):
            guard let ownApp else { throw CapturePreparationError.overlayUnavailable }
            let exceptions = content.windows.filter { windowIDs.contains($0.windowID) }
            filter = SCContentFilter(display: display, excludingApplications: [ownApp],
                                     exceptingWindows: exceptions)
        }
        let pixelSize = try CapturePixelSize(contentRect: filter.contentRect,
                                             pointPixelScale: CGFloat(filter.pointPixelScale),
                                             expectedPixelSize: request.expectedPixelSize)
        let config = SCStreamConfiguration()
        config.width = pixelSize.width
        config.height = pixelSize.height
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        return PreparedCapture(filter: filter, configuration: config, pixelSize: pixelSize)
    }

    func screenshot(displayID: CGDirectDisplayID) async throws -> CVPixelBuffer {
        guard let request, request.displayID == displayID, request.excludedWindowID != 0 else {
            throw CapturePreparationError.overlayUnavailable
        }
        let token = generation
        let prepared = try await metadata.value { try await Self.prepareMetadata(for: request) }
        try Task.checkCancellation()
        guard token == generation, self.request == request else { throw CancellationError() }
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: prepared.filter,
                                                                      configuration: prepared.configuration)
        try Task.checkCancellation()
        guard token == generation, self.request == request else { throw CancellationError() }
        guard sample.isValid, let buffer = sample.imageBuffer else {
            throw CapturePreparationError.pixelsUnavailable
        }
        guard prepared.pixelSize.matches(buffer) else {
            invalidate()
            throw CapturePreparationError.displaySizeChanged
        }
        return buffer
    }
}
