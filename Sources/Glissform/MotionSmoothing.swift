import Foundation

/// Reconstructs whole-degree readings without predicting unreported lid motion.
/// Sensor samples advance an analytic trajectory; display queries never change
/// its cadence or history, even when rendering runs ahead to a presentation time.
struct MotionSmoothing {
    private(set) var value: Float = 0
    private(set) var velocity: Double = 0
    private var sampleValue: Float = 0
    private var sampleVelocity: Double = 0
    private var sampleTime: Double?
    private var target: Float = 0
    private var direction: Float = 0
    private var targetChangeTime: Double?
    private var timeConstant = 0.020
    private var degreeInterval = 1.0 / 30
    private var hasCadence = false
    private var compatibilityTime: Double = 0
    private var lastPresentationTime: Double?

    mutating func reset(to value: Float = 0, at time: Double? = nil) {
        self.value = value
        velocity = 0
        sampleValue = value
        sampleVelocity = 0
        sampleTime = time.flatMap { $0.isFinite ? $0 : nil }
        target = value
        direction = 0
        targetChangeTime = sampleTime
        timeConstant = 0.020
        degreeInterval = 1.0 / 30
        hasCadence = false
        compatibilityTime = sampleTime ?? 0
        lastPresentationTime = nil
    }

    mutating func ingest(target nextTarget: Float, at time: Double) {
        guard nextTarget.isFinite, time.isFinite,
              sampleTime.map({ time >= $0 }) ?? true else { return }
        if let sampleTime {
            let state = response(from: sampleValue, velocity: sampleVelocity,
                                 elapsed: time - sampleTime)
            sampleValue = state.value
            sampleVelocity = state.velocity
        }
        sampleTime = time
        let change = nextTarget - target
        guard change != 0 else { return }
        let nextDirection: Float = change > 0 ? 1 : -1
        let reversing = direction != 0 && nextDirection != direction
        if reversing { sampleVelocity = 0 }
        let degrees = max(1, Double(abs(change)) * 180 / .pi)
        let interval = min(0.5, max(0.000001, time - (targetChangeTime ?? (time - 1.0 / 30))) / degrees)
        // Degree cadence belongs to the acquisition clock, not to queue delivery
        // or the display callback. Repeated samples retain the last change time.
        if direction == 0 || reversing {
            degreeInterval = interval
            hasCadence = false
        } else if !hasCadence {
            degreeInterval = interval
            hasCadence = true
        } else {
            degreeInterval = degreeInterval * 0.85 + interval * 0.15
        }
        let movingResponse = 0.035 * pow(min(1, degreeInterval * 30), 0.7)
        timeConstant = reversing || abs(change) > 0.1 ? 0.0125
            : min(0.100, max(movingResponse, degreeInterval * 0.35))
        direction = nextDirection
        target = nextTarget
        targetChangeTime = time
    }

    /// Evaluates only the known target's settling trajectory. A future display
    /// timestamp never extrapolates the lid beyond the latest reported angle.
    mutating func step(at time: Double) -> Float {
        guard time.isFinite, let sampleTime, time >= sampleTime,
              lastPresentationTime.map({ time >= $0 }) ?? true else { return value }
        lastPresentationTime = time
        let state = response(from: sampleValue, velocity: sampleVelocity, elapsed: time - sampleTime)
        value = state.value
        velocity = state.velocity
        return value
    }

    /// Convenience for deterministic callers with a target for each interval.
    mutating func step(toward target: Float, elapsed: Double) -> Float {
        guard target.isFinite, elapsed.isFinite, elapsed > 0 else { return value }
        ingest(target: target, at: compatibilityTime)
        compatibilityTime += elapsed
        return step(at: compatibilityTime)
    }

    private func response(from origin: Float, velocity initialVelocity: Double,
                          elapsed: Double) -> (value: Float, velocity: Double) {
        guard elapsed > 0 else { return (origin, initialVelocity) }
        let decay = exp(-elapsed / timeConstant)
        let error = Double(origin) - Double(target)
        let coefficient = initialVelocity + error / timeConstant
        let next = Double(target) + (error + coefficient * elapsed) * decay
        let nextVelocity = (initialVelocity - coefficient * elapsed / timeConstant) * decay
        // Bound sudden stops and finish exactly so rendering can pause at rest.
        if (Double(target) - Double(origin)) * (Double(target) - next) <= 0
            || (abs(Double(target) - next) < 0.00005 && abs(nextVelocity) < 0.003) {
            return (target, 0)
        }
        return (Float(next), nextVelocity)
    }
}

/// A bounded quintic handoff that can preserve motion already on screen.
struct HandoffTransition {
    static let duration: Double = 0.100
    private var origin: Float = 0
    private var initialVelocity: Double = 0
    private var transitionDuration = Self.duration
    private var elapsed: Double = 0
    private(set) var velocity: Double = 0
    private(set) var active = false
    private var firstFrame = false

    mutating func begin(from value: Float, velocity: Double = 0, duration: Double = Self.duration,
                        holdFirstFrame: Bool = true) {
        origin = value
        initialVelocity = velocity.isFinite ? velocity : 0
        self.velocity = initialVelocity
        transitionDuration = duration.isFinite ? min(0.300, max(0.060, duration)) : Self.duration
        firstFrame = holdFirstFrame
        elapsed = 0
        active = true
    }

    mutating func step(toward target: Float, velocity targetVelocity: Double = 0, elapsed delta: Double) -> Float {
        guard active else {
            velocity = targetVelocity.isFinite ? targetVelocity : 0
            return target
        }
        let distance = Double(target - origin)
        // A velocity directed away from the destination cannot be preserved
        // without moving outside the handoff. Bound the remaining tangent so
        // the fixed-target quintic remains monotonic and cannot overshoot.
        let tangent = distance == 0 ? 0 : min(2, max(0, initialVelocity * transitionDuration / distance))
        let startVelocity = distance * tangent / transitionDuration
        if firstFrame {
            firstFrame = false
            velocity = startVelocity
            return origin
        }
        if delta.isFinite { elapsed += max(0, delta) }
        let t = min(1, elapsed / transitionDuration)
        let blend = t * t * t * (t * (t * 6 - 15) + 10)
        let tangentBlend = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
        let blendDerivative = 30 * t * t * (1 - t) * (1 - t)
        let tangentDerivative = 1 - 18 * t * t + 32 * pow(t, 3) - 15 * pow(t, 4)
        velocity = distance * blendDerivative / transitionDuration + startVelocity * tangentDerivative
            + blend * (targetVelocity.isFinite ? targetVelocity : 0)
        if t == 1 {
            active = false
            velocity = targetVelocity.isFinite ? targetVelocity : 0
            return target
        }
        let next = Double(origin) + distance * blend + startVelocity * transitionDuration * tangentBlend
        return Float(min(max(next, Double(min(origin, target))), Double(max(origin, target))))
    }
}
