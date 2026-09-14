import Foundation

/// Reconstructs whole-degree sensor steps without predicting unreported motion.
struct MotionSmoothing {
    private(set) var value: Float = 0
    private var leadingValue: Double = 0
    private var previousTarget: Float = 0
    private var direction: Float = 0
    private var sinceTargetChange: Double = 0
    private var timeConstant = 0.0125

    mutating func reset(to value: Float = 0) {
        self.value = value
        leadingValue = Double(value)
        previousTarget = value
        direction = 0
        sinceTargetChange = 0
        timeConstant = 0.0125
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
                leadingValue = Double(value)
            }
            // One physical degree becomes ~0.015 radians in the renderer.
            // Spread small changes across their measured interval. Large changes
            // and reversals keep the fast response (95% within 60 ms).
            if abs(change) <= 0.018 && !reversing {
                timeConstant = min(0.100, max(0.035, sinceTargetChange * 0.35))
            } else {
                timeConstant = 0.0125
            }
            direction = nextDirection
            previousTarget = target
            sinceTargetChange = 0
        }

        // Exact solution of two cascaded exponential filters: continuous speed
        // across targets, independent of frame rate, no extrapolation or overshoot.
        let decay = exp(-elapsed / timeConstant)
        let leadError = leadingValue - Double(target)
        let valueError = Double(value) - Double(target)
        value = Float(Double(target) + (valueError + leadError * elapsed / timeConstant) * decay)
        leadingValue = Double(target) + leadError * decay
        if abs(target - value) < 0.00005 && abs(Double(target) - leadingValue) < 0.00005 {
            value = target
            leadingValue = Double(target)
        }
        return value
    }
}

/// A boundary handoff with zero speed and acceleration at both ends.
struct HandoffTransition {
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
        let t = min(1, elapsed / 0.180)
        let blend = Float(t * t * t * (t * (t * 6 - 15) + 10))
        if t == 1 { active = false }
        return origin + (target - origin) * blend
    }
}
