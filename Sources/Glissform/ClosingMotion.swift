import Foundation

/// A gesture keeps its original image plane through any direction changes.
struct ClosingMotion {
    static let defaultStillDuration = 1.0
    static func validStillDuration(_ value: Double) -> Double {
        value.isFinite ? min(10, max(0.5, (value * 2).rounded() / 2)) : defaultStillDuration
    }
    static func validDetectionThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return 20 }
        return value <= 0 ? 0 : min(130, max(20, value)).rounded()
    }
    private(set) var activationAngle: Double = 80
    var startAngle: Double?
    var automaticStartAngle = false {
        didSet {
            guard automaticStartAngle != oldValue else { return }
            learnedStartAngle = nil
            reset()
        }
    }
    var automaticDetectionThreshold = 20.0 {
        didSet {
            guard automaticDetectionThreshold != oldValue, automaticStartAngle else { return }
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
    var pauseDuration: Double = Self.defaultStillDuration { didSet { clearPauseTracking() } }
    var automaticAngleDuration: Double = Self.defaultStillDuration { didSet { clearRestingTracking() } }
    private(set) var desktopResumed = false
    private var desktopResumeRearmAngle: Double?
    private var desktopResumeCanRearmByClosing = false
    private var escapeRearmAngle: Double?
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
              angle.isFinite, (20...130).contains(angle),
              angle > Self.validDetectionThreshold(automaticDetectionThreshold), time.isFinite else {
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
        if time - (restingSince ?? time) >= Self.validStillDuration(automaticAngleDuration) {
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
        let duration = Self.validStillDuration(pauseDuration)
        return time - (stillSince ?? time) >= duration
    }

    mutating func reset() {
        armed = false
        hasReference = false
        active = false
        desktopResumed = false
        desktopResumeRearmAngle = nil
        desktopResumeCanRearmByClosing = false
        escapeRearmAngle = nil
        clearPauseTracking()
        clearRestingTracking()
    }

    mutating func cancelUntilOpened(above angle: Double) {
        reset()
        escapeRearmAngle = angle
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

    /// The visible return has finished before the lid reaches the old start
    /// angle. Keep the desktop live at that position without recapturing it.
    mutating func completeAssistedOpening(at angle: Double) {
        guard angle.isFinite, let startAngle = effectiveStartAngle else { return }
        active = false
        clearPauseTracking()
        clearRestingTracking()
        if angle >= startAngle {
            armed = true
            return
        }
        armed = false
        desktopResumed = true
        desktopResumeRearmAngle = angle
        desktopResumeCanRearmByClosing = automaticStartAngle && (20...130).contains(angle)
            && angle > Self.validDetectionThreshold(automaticDetectionThreshold)
        if desktopResumeCanRearmByClosing {
            learnedStartAngle = automaticThreshold(below: angle)
        } else if automaticStartAngle {
            learnedStartAngle = nil
        }
    }

    mutating func update(angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) -> Float {
        guard angle.isFinite, (0...180).contains(angle) else {
            clearPauseTracking()
            clearRestingTracking()
            return 0
        }
        if let escapeRearmAngle {
            guard angle > escapeRearmAngle else { return 0 }
            self.escapeRearmAngle = nil
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
                    && angle > Self.validDetectionThreshold(automaticDetectionThreshold)
                if desktopResumeCanRearmByClosing {
                    learnedStartAngle = automaticThreshold(below: angle)
                } else if automaticStartAngle {
                    learnedStartAngle = nil
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

/// Uses recent upward sensor movement to start the final opening return.
/// A small direction wobble cannot start it, and old samples cannot set speed.
struct OpeningAssist {
    static let remainingDegrees = 5.0
    private var previous: (angle: Double, time: Double)?
    private var rising: [(angle: Double, time: Double)] = []

    mutating func reset() {
        previous = nil
        rising.removeAll(keepingCapacity: true)
    }

    mutating func observe(angle: Double, time: Double, referenceAngle: Double,
                          active: Bool) -> Double? {
        guard active, angle.isFinite, time.isFinite, referenceAngle.isFinite else {
            reset()
            return nil
        }
        defer { previous = (angle, time) }
        guard let previous, time > previous.time, time - previous.time <= 1.25 else {
            rising.removeAll(keepingCapacity: true)
            return nil
        }
        let movement = angle - previous.angle
        if movement < -0.25 {
            rising.removeAll(keepingCapacity: true)
            return nil
        }
        guard movement > 0.08 else { return nil }
        if rising.isEmpty { rising.append(previous) }
        rising.append((angle, time))
        while rising.count > 2 && time - rising[0].time > 1.2 { rising.removeFirst() }
        guard angle >= referenceAngle - Self.remainingDegrees, angle < referenceAngle,
              let first = rising.first, angle - first.angle >= 1.5,
              time > first.time else { return nil }
        // The earlier samples establish direction; the most recent 80 ms
        // sets the pace when the hand reaches the assisted region.
        let recent = rising.first(where: { $0.time < time && time - $0.time <= 0.080 })
            ?? rising[rising.count - 2]
        return (angle - recent.angle) / (time - recent.time)
    }
}
