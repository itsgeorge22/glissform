import Foundation

/// Reconstructs whole-degree sensor steps without predicting unreported motion.
struct MotionSmoothing {
    private(set) var value: Float = 0
    private var velocity: Double = 0
    private var previousTarget: Float = 0
    private var direction: Float = 0
    private var sinceTargetChange: Double = 0
    private var timeConstant = 0.020
    private var degreeInterval = 1.0 / 30
    private var hasCadence = false

    mutating func reset(to value: Float = 0) {
        self.value = value
        velocity = 0
        previousTarget = value
        direction = 0
        sinceTargetChange = 0
        timeConstant = 0.020
        degreeInterval = 1.0 / 30
        hasCadence = false
    }

    mutating func step(toward target: Float, elapsed: Double) -> Float {
        guard target.isFinite, elapsed.isFinite, elapsed > 0 else { return value }
        sinceTargetChange += elapsed
        let change = target - previousTarget
        if change != 0 {
            let nextDirection: Float = change > 0 ? 1 : -1
            let reversing = direction != 0 && nextDirection != direction
            if reversing {
                // Discard the old direction immediately, without carrying momentum.
                velocity = 0
            }
            let degrees = max(1, Double(abs(change)) * 180 / .pi)
            let interval = min(0.5, sinceTargetChange / degrees)
            // Seed from a complete interval, then average cadence so alternating
            // one/two-degree reports cannot switch between slow and fast filters.
            if direction == 0 || reversing {
                degreeInterval = interval
                hasCadence = false
            } else if !hasCadence {
                degreeInterval = interval
                hasCadence = true
            } else {
                degreeInterval = degreeInterval * 0.85 + interval * 0.15
            }
            // Retain gentle interpolation for sparse reports; smoothly shorten
            // the response as speed rises above one degree per sensor poll.
            let movingResponse = 0.035 * pow(min(1, degreeInterval * 30), 0.7)
            timeConstant = reversing || abs(change) > 0.1 ? 0.0125
                : min(0.100, max(movingResponse, degreeInterval * 0.35))
            direction = nextDirection
            previousTarget = target
            sinceTargetChange = 0
        }

        // Exact critically damped response. Keep velocity explicitly so changing
        // the response time does not introduce a speed discontinuity.
        let decay = exp(-elapsed / timeConstant)
        let valueError = Double(value) - Double(target)
        let coefficient = velocity + valueError / timeConstant
        let next = Double(target) + (valueError + coefficient * elapsed) * decay
        velocity = (velocity - coefficient * elapsed / timeConstant) * decay
        // A sudden stop can leave more velocity than the remaining distance.
        // Never let it carry the image beyond the angle actually reported.
        if (Double(target) - Double(value)) * (Double(target) - next) <= 0 {
            value = target
            velocity = 0
        } else {
            value = Float(next)
        }
        if abs(target - value) < 0.00005 && abs(velocity) < 0.003 {
            value = target
            velocity = 0
        }
        return value
    }
}

/// A boundary handoff with zero speed and acceleration at both ends.
struct HandoffTransition {
    static let duration: Double = 0.100
    private var origin: Float = 0
    private var elapsed: Double = 0
    private(set) var active = false
    private var firstFrame = false

    mutating func begin(from value: Float) {
        origin = value
        firstFrame = true
        elapsed = 0
        active = true
    }

    mutating func step(toward target: Float, elapsed delta: Double) -> Float {
        guard active else { return target }
        // The first displayed frame is exactly the origin, even after a delayed
        // capture or display callback. Time starts only after that frame.
        if firstFrame {
            firstFrame = false
            return origin
        }
        elapsed += max(0, delta)
        let t = min(1, elapsed / Self.duration)
        let blend = Float(t * t * t * (t * (t * 6 - 15) + 10))
        if t == 1 { active = false }
        return origin + (target - origin) * blend
    }
}
