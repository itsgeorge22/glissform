import Foundation

/// A gesture keeps its original image plane through any direction changes.
struct ClosingMotion {
    private(set) var activationAngle: Double = 80
    var startAngle: Double?
    var automaticStartAngle = false {
        didSet {
            guard automaticStartAngle != oldValue else { return }
            learnedStartAngle = nil
            reset()
        }
    }
    private(set) var learnedStartAngle: Double?
    var effectiveStartAngle: Double? {
        automaticStartAngle ? (learnedStartAngle ?? startAngle) : startAngle
    }
    private var armed = false
    private var hasReference = false
    private(set) var active = false
    var resumeAfterPause = false { didSet { clearPauseTracking() } }
    var pauseDuration: Double = 2 { didSet { clearPauseTracking() } }
    private(set) var desktopResumed = false
    private var desktopResumeRearmAngle: Double?
    private var desktopResumeCanRearmByClosing = false
    private var stillSince: Double?
    private var lastSampleTime: Double?
    private var lowestAngle = 0.0
    private var highestAngle = 0.0
    private var restingSince: Double?
    private var restingLastSampleTime: Double?
    private var restingLowestAngle = 0.0
    private var restingHighestAngle = 0.0

    private mutating func clearRestingTracking() {
        restingSince = nil
        restingLastSampleTime = nil
    }

    private func automaticThreshold(below angle: Double) -> Double {
        angle.rounded() - 1
    }

    private mutating func learnRestingAngle(_ angle: Double, time: Double) {
        guard automaticStartAngle, !active, !desktopResumed,
              angle.isFinite, (20...130).contains(angle), time.isFinite else {
            clearRestingTracking()
            return
        }
        if let learnedStartAngle, abs((learnedStartAngle + 1) - angle) <= 1 {
            clearRestingTracking()
            return
        }
        if restingSince == nil || restingLastSampleTime.map({ time < $0 || time - $0 > 0.25 }) == true {
            restingSince = time
            restingLowestAngle = angle
            restingHighestAngle = angle
        }
        restingLowestAngle = min(restingLowestAngle, angle)
        restingHighestAngle = max(restingHighestAngle, angle)
        if restingHighestAngle - restingLowestAngle > 1 {
            restingSince = time
            restingLowestAngle = angle
            restingHighestAngle = angle
        }
        restingLastSampleTime = time
        if time - (restingSince ?? time) >= 2 {
            learnedStartAngle = automaticThreshold(below: angle)
            clearRestingTracking()
        }
    }

    private mutating func clearPauseTracking() {
        stillSince = nil
        lastSampleTime = nil
    }

    private mutating func pauseExpired(angle: Double, time: Double) -> Bool {
        guard resumeAfterPause, time.isFinite else { clearPauseTracking(); return false }
        // Missing samples are not evidence of a still lid. Ignore one degree
        // of sensor chatter, but measure the whole band so slow drift accumulates.
        if stillSince == nil || lastSampleTime.map({ time < $0 || time - $0 > 0.25 }) == true {
            stillSince = time
            lowestAngle = angle
            highestAngle = angle
        }
        lowestAngle = min(lowestAngle, angle)
        highestAngle = max(highestAngle, angle)
        if highestAngle - lowestAngle > 1 {
            stillSince = time
            lowestAngle = angle
            highestAngle = angle
        }
        lastSampleTime = time
        let duration = pauseDuration.isFinite ? min(10, max(0.5, pauseDuration)) : 2
        return time - (stillSince ?? time) >= duration
    }

    mutating func reset() {
        armed = false
        hasReference = false
        active = false
        desktopResumed = false
        desktopResumeRearmAngle = nil
        desktopResumeCanRearmByClosing = false
        clearPauseTracking()
        clearRestingTracking()
    }

    /// Only the wake coordinator may arm below the threshold, after fresh
    /// upward readings. Ordinary startup and setting changes remain unarmed.
    mutating func beginOpening(angle: Double, time: Double) -> Float {
        guard let referenceAngle = effectiveStartAngle, angle.isFinite,
              (0..<referenceAngle).contains(angle) else { return 0 }
        reset()
        armed = true
        clearRestingTracking()
        return update(angle: angle, time: time)
    }

    mutating func update(angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) -> Float {
        guard angle.isFinite, (0...180).contains(angle) else {
            clearPauseTracking()
            clearRestingTracking()
            return 0
        }
        learnRestingAngle(angle, time: time)
        if let startAngle = effectiveStartAngle {
            if desktopResumed {
                let openedPastRest = angle > max(startAngle, desktopResumeRearmAngle ?? startAngle)
                let closedPastLearnedStart = desktopResumeCanRearmByClosing && angle < startAngle
                guard openedPastRest || closedPastLearnedStart else { return 0 }
                desktopResumed = false
                desktopResumeRearmAngle = nil
                desktopResumeCanRearmByClosing = false
                armed = true
            }
            activationAngle = startAngle
            if angle >= startAngle {
                armed = true
                active = false
                clearPauseTracking()
                return 0
            }
            guard armed else { return 0 }
            active = true
            if pauseExpired(angle: angle, time: time) {
                desktopResumeCanRearmByClosing = automaticStartAngle && (20...130).contains(angle)
                if desktopResumeCanRearmByClosing {
                    learnedStartAngle = automaticThreshold(below: angle)
                }
                active = false
                armed = false
                desktopResumed = true
                desktopResumeRearmAngle = angle
                clearPauseTracking()
                clearRestingTracking()
                return 0
            }
            let raw = min(1, max(0, (startAngle - angle) / max(1, startAngle - 4)))
            return Float(raw * raw * (3 - 2 * raw))
        }
        guard hasReference else {
            hasReference = true
            activationAngle = angle
            return 0
        }
        if active {
            if angle >= activationAngle {
                active = false
                activationAngle = angle
                return 0
            }
        } else {
            // Preserve the image plane at the user's resting angle. Two degrees
            // of deadband ignore sensor quantization without waiting until 85°.
            activationAngle = max(activationAngle, angle)
            guard angle < activationAngle - 2 else { return 0 }
            active = true
        }
        guard active else { return 0 }
        let raw = min(1, max(0, (activationAngle - angle) / max(1, activationAngle - 4)))
        return Float(raw * raw * (3 - 2 * raw))
    }
}
