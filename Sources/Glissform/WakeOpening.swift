import Foundation

/// Numeric eligibility for presenting a retained closing frame; owns no pixels.
struct WakeOpening {
    enum Decision: Equatable {
        case waiting, prepare, skip(String)
    }

    static let deadline = 3.0
    private var eligible = false
    private(set) var startedAt: Double?
    private(set) var preparing = false
    private var lastSample: (angle: Double, time: Double)?
    private var lowestAngle = 180.0
    private var peakAngle = 0.0

    var pending: Bool { startedAt != nil }
    var awaitingWake: Bool { eligible }

    mutating func prepareForSleep(angle: Double?, sampleAge: Double) {
        self = WakeOpening()
        eligible = angle.map { $0.isFinite && (0...20).contains($0) } == true
            && sampleAge.isFinite && (0...1).contains(sampleAge)
    }

    @discardableResult mutating func resume(time: Double) -> Bool {
        guard eligible, startedAt == nil, time.isFinite else { return false }
        eligible = false
        startedAt = time
        return true
    }

    mutating func observe(angle: Double, time: Double, referenceAngle: Double,
                          desktopAvailable: Bool) -> Decision {
        guard let startedAt else { return .waiting }
        guard time.isFinite, time >= startedAt, time - startedAt <= Self.deadline else {
            return .skip("wake window expired")
        }
        guard angle.isFinite, (0...180).contains(angle), referenceAngle.isFinite else {
            return .skip("invalid sensor reading")
        }
        guard angle < referenceAngle - 3 else { return .skip("lid already open") }
        if preparing {
            guard desktopAvailable else { return .skip("desktop unavailable") }
            guard angle >= peakAngle - 2 else { return .skip("reversed before reveal") }
        }
        if let lastSample, time < lastSample.time || time - lastSample.time > 0.25 {
            if preparing { return .skip("sensor gap") }
            lowestAngle = angle
        }
        let rising = lastSample.map { angle > $0.angle && time >= $0.time && time - $0.time <= 0.25 } == true
        lowestAngle = min(lowestAngle, angle)
        peakAngle = max(peakAngle, angle)
        lastSample = (angle, time)
        guard !preparing, desktopAvailable, rising, angle >= lowestAngle + 2 else { return .waiting }
        preparing = true
        peakAngle = angle
        return .prepare
    }

    func canPresent(time: Double, referenceAngle: Double, desktopAvailable: Bool) -> Bool {
        guard preparing, let startedAt, let lastSample else { return false }
        return desktopAvailable && time >= startedAt && time - startedAt <= Self.deadline
            && time >= lastSample.time && time - lastSample.time <= 0.25
            && lastSample.angle < referenceAngle - 3
    }

    func expired(time: Double) -> Bool {
        guard let startedAt else { return false }
        return time - startedAt > Self.deadline
    }
}
