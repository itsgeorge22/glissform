import AppKit
import CoreVideo

@main struct CaptureChecks {
    @MainActor static func main() async throws {
        let retina = try CapturePixelSize(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                          pointPixelScale: 2,
                                          expectedPixelSize: CGSize(width: 3840, height: 2486))
        precondition(retina.width == 3840 && retina.height == 2486,
                     "Scaled display modes must capture backing pixels, not logical mode dimensions")
        let ordinary = try CapturePixelSize(contentRect: CGRect(x: 100, y: 200, width: 1920, height: 1080),
                                            pointPixelScale: 1,
                                            expectedPixelSize: CGSize(width: 1920, height: 1080))
        precondition(ordinary.width == 1920 && ordinary.height == 1080)
        for (scale, expected) in [(CGFloat(2), CGSize(width: 1920, height: 1243)),
                                  (CGFloat(0), CGSize(width: 3840, height: 2486)),
                                  (CGFloat.nan, CGSize(width: 3840, height: 2486)),
                                  (CGFloat(2), CGSize(width: CGFloat.infinity, height: 2486))] {
            do {
                _ = try CapturePixelSize(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                                         pointPixelScale: scale, expectedPixelSize: expected)
                preconditionFailure("Invalid or mismatched backing dimensions must fail closed")
            } catch CapturePreparationError.displaySizeChanged {}
        }
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1243,
                                         kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        precondition(!retina.matches(buffer!), "An unexpectedly downscaled screenshot must be rejected")
        print("PASS: capture dimensions follow filter backing scale and reject downscaled/mismatched output")

        let windows = [CaptureWindowIdentity(windowID: 10, ownerPID: 42),
                       CaptureWindowIdentity(windowID: 20, ownerPID: 42),
                       CaptureWindowIdentity(windowID: 30, ownerPID: 100),
                       CaptureWindowIdentity(windowID: 40, ownerPID: nil)]
        let ordinaryExclusion = try CaptureExclusionPlan.make(excludingWindowID: 10, ownPID: 42,
                                                             applicationAvailable: true, windows: windows)
        precondition(ordinaryExclusion == .window(10), "Only the overlay must be excluded when identified")
        let hiddenExclusion = try CaptureExclusionPlan.make(excludingWindowID: 10, ownPID: 42,
                                                           applicationAvailable: true,
                                                           windows: Array(windows.dropFirst()))
        precondition(hiddenExclusion == .application(exceptingWindowIDs: [20]),
                     "Missing overlay metadata must exclude our app, preserving only known other own windows")
        let noOwnWindows = try CaptureExclusionPlan.make(excludingWindowID: 10, ownPID: 42,
                                                        applicationAvailable: true,
                                                        windows: Array(windows.dropFirst(2)))
        precondition(noOwnWindows == .application(exceptingWindowIDs: []),
                     "Other apps and unknown owners must never become exclusion exceptions")
        for (excludedID, available) in [(CGWindowID(0), true), (10, false), (30, true), (40, true)] {
            do {
                _ = try CaptureExclusionPlan.make(excludingWindowID: excludedID, ownPID: 42,
                                                   applicationAvailable: available,
                                                   windows: Array(windows.dropFirst()))
                preconditionFailure("Unknown app or foreign/missing overlay identity must fail closed")
            } catch CapturePreparationError.overlayUnavailable {}
        }
        print("PASS: hidden-overlay fallback preserves Settings without including overlay or unrelated windows")

        var time = 100.0
        let cache = CaptureMetadataCache<Int>(lifetime: 30, now: { time })
        var loads = 0
        func load() -> Int { loads += 1; return loads }
        let first = try await cache.value { load() }
        time = 129
        let reused = try await cache.value { load() }
        precondition(first == 1 && reused == 1 && loads == 1)
        time = 131
        let refreshed = try await cache.value { load() }
        precondition(refreshed == 2 && loads == 2, "Old metadata must be refreshed before capture")
        cache.invalidate()
        let invalidated = try await cache.value { load() }
        precondition(invalidated == 3, "Display/session invalidation must drop cached metadata")

        cache.invalidate()
        var pending: CheckedContinuation<Int, Never>?
        let old = Task { @MainActor in
            try await cache.value { await withCheckedContinuation { pending = $0 } }
        }
        while pending == nil { await Task.yield() }
        cache.invalidate()
        let replacement = try await cache.value { 50 }
        pending?.resume(returning: 40)
        do {
            _ = try await old.value
            preconditionFailure("A late discovery from an invalidated session must be rejected")
        } catch is CancellationError {}
        let afterLateResult = try await cache.value { 60 }
        precondition(replacement == 50 && afterLateResult == 50,
                     "Stale completion must not overwrite the replacement metadata")
        print("PASS: metadata lifetime, explicit invalidation and late discovery rejection")

        cache.invalidate()
        pending = nil
        var sharedLoads = 0
        let prewarm = Task { @MainActor in
            try await cache.value {
                sharedLoads += 1
                return await withCheckedContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        let gesture = Task { @MainActor in
            try await cache.value { sharedLoads += 1; return 99 }
        }
        prewarm.cancel()
        pending?.resume(returning: 70)
        do {
            _ = try await prewarm.value
            preconditionFailure("A cancelled waiter must not receive capture metadata")
        } catch is CancellationError {}
        let sharedResult = try await gesture.value
        precondition(sharedResult == 70 && sharedLoads == 1,
                     "A gesture must reuse discovery even if its prewarm waiter was cancelled")
        print("PASS: concurrent preparation shares discovery without cross-cancelling the gesture")

        cache.invalidate()
        pending = nil
        let abandoned = Task { @MainActor in
            try await cache.value { await withCheckedContinuation { pending = $0 } }
        }
        while pending == nil { await Task.yield() }
        abandoned.cancel()
        pending?.resume(returning: 80)
        do { _ = try await abandoned.value; preconditionFailure("Cancelled preparation must stop") }
        catch is CancellationError {}
        time += 31
        let afterAbandoned = try await cache.value { 90 }
        precondition(afterAbandoned == 90,
                     "Completed discovery with no remaining waiter must still expire from its completion time")
        print("PASS: abandoned preparation cannot turn expired metadata into a fresh cache entry")

        let capture = DesktopCapture()
        do {
            _ = try await capture.screenshot(displayID: 1)
            preconditionFailure("Capture without a configured overlay must fail closed")
        } catch CapturePreparationError.overlayUnavailable {}
        do {
            try await capture.prepare(displayID: 1, excludingWindowID: 0,
                                      expectedPixelSize: CGSize(width: 1, height: 1))
            preconditionFailure("A missing overlay ID must fail before any content discovery")
        } catch CapturePreparationError.overlayUnavailable {}
        capture.invalidate()
        print("PASS: absent overlay exclusion fails without requesting any desktop pixels")
    }
}
