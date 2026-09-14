import Foundation

/// A gesture keeps its original image plane through any direction changes.
struct ClosingMotion {
    private(set) var activationAngle: Double = 80
    var startAngle: Double?
    private var armed = false
    private var hasReference = false
    private(set) var active = false

    mutating func reset() {
        armed = false
        hasReference = false
        active = false
    }

    mutating func update(angle: Double) -> Float {
        guard angle.isFinite, (0...180).contains(angle) else { return 0 }
        if let startAngle {
            activationAngle = startAngle
            if angle >= startAngle {
                armed = true
                active = false
                return 0
            }
            guard armed else { return 0 }
            active = true
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
