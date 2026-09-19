import Foundation

/// A gesture keeps its original image plane through any direction changes.
struct ClosingMotion {
    private(set) var activationAngle: Double = 80
    var startAngle: Double?
    private var armed = false
    private var hasReference = false
    private(set) var active = false
    var resumeAfterPause = false { didSet { clearPauseTracking() } }
    var pauseDuration: Double = 2 { didSet { clearPauseTracking() } }
    private(set) var desktopResumed = false
    private var stillSince: Double?
    private var lastSampleTime: Double?
    private var lowestAngle = 0.0
    private var highestAngle = 0.0

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
        clearPauseTracking()
    }

    mutating func update(angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) -> Float {
        guard angle.isFinite, (0...180).contains(angle) else { clearPauseTracking(); return 0 }
        if let startAngle {
            activationAngle = startAngle
            if desktopResumed {
                guard angle > startAngle else { return 0 }
                desktopResumed = false
            }
            if angle >= startAngle {
                armed = true
                active = false
                clearPauseTracking()
                return 0
            }
            guard armed else { return 0 }
            active = true
            if pauseExpired(angle: angle, time: time) {
                active = false
                armed = false
                desktopResumed = true
                clearPauseTracking()
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
