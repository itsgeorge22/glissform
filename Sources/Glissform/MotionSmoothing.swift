import Foundation

/// Smooths lid readings without extrapolating sensor motion.
/// Sensor samples advance an analytic trajectory; display queries never change
/// its cadence or history, even when rendering runs ahead to a presentation time.
struct MotionSmoothing {
    private(set) var value: Float = 0
    private(set) var velocity: Double = 0
    private var sampleValue: Float = 0
    private var sampleVelocity: Double = 0
    private var sampleTime: Double?
    private(set) var target: Float = 0
    private var direction: Float = 0
    private var targetChangeTime: Double?
    private var timeConstant = 0.020
    private var degreeInterval = 1.0 / 30
    private var hasCadence = false
    private var intervals: [Double] = []
    private var pendingReversal: (target: Float, since: Double)?
    private var compatibilityTime: Double = 0
    private var lastPresentationTime: Double?
    private let noiseFloor = Float(0.08 * .pi / 180)

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
        intervals.removeAll(keepingCapacity: true)
        pendingReversal = nil
        compatibilityTime = sampleTime ?? 0
        lastPresentationTime = nil
    }

    mutating func ingest(target nextTarget: Float, at time: Double) {
        guard nextTarget.isFinite, time.isFinite,
              sampleTime.map({ time >= $0 }) ?? true else { return }
        if let sampleTime {
            if time - sampleTime > 0.100 { pendingReversal = nil }
            let state = response(from: sampleValue, velocity: sampleVelocity,
                                 elapsed: time - sampleTime)
            sampleValue = state.value
            sampleVelocity = state.velocity
        }
        sampleTime = time
        let change = nextTarget - target
        guard change != 0 else {
            pendingReversal = nil
            return
        }
        guard nextTarget == 0 || abs(change) >= noiseFloor else {
            // Fractional HID reports fluctuate by a few hundredths of a degree
            // even when the lid is still. Keep the last meaningful target.
            return
        }
        let nextDirection: Float = change > 0 ? 1 : -1
        let reversing = direction != 0 && nextDirection != direction
        // A backwards movement under one degree may be boundary chatter.
        // Confirm the direction over 50 ms even as fractional readings change.
        // This gate affects only presentation, never gesture/sleep decisions.
        if reversing && nextTarget != 0 && abs(change) < Float(1.1 * .pi / 180) {
            if pendingReversal == nil {
                pendingReversal = (nextTarget, time)
                return
            }
            if time - (pendingReversal?.since ?? time) < 0.050 { return }
        }
        pendingReversal = nil
        // Fractional readings can be much smaller than one degree. Preserve
        // their measured cadence, but cap the response to a quarter-degree
        // step so very slow motion does not acquire excessive lag.
        let degrees = max(0.25, Double(abs(change)) * 180 / .pi)
        let interval = min(0.5, max(0.000001, time - (targetChangeTime ?? (time - 1.0 / 30))) / degrees)
        // Degree cadence belongs to the acquisition clock, not to queue delivery
        // or the display callback. Repeated samples retain the last change time.
        if direction == 0 || reversing {
            degreeInterval = interval
            hasCadence = false
            intervals.removeAll(keepingCapacity: true)
        } else if !hasCadence {
            degreeInterval = interval
            hasCadence = true
            intervals = [interval]
        } else {
            intervals.append(interval)
            if intervals.count > 4 { intervals.removeFirst() }
            degreeInterval = intervals.reduce(0, +) / Double(intervals.count)
        }
        let movingResponse = 0.035 * pow(min(1, degreeInterval * 30), 0.7)
        let desiredResponse = min(0.118, max(0.024, movingResponse, degreeInterval * 0.43))
        if direction == 0 {
            timeConstant = abs(change) > 0.1 ? 0.0125 : 0.035
        } else if reversing {
            // Brake the existing momentum instead of deleting it. A real
            // reversal remains responsive without the old 12.5 ms kick.
            timeConstant = min(timeConstant, 0.045)
        } else {
            let elapsed = max(0, time - (targetChangeTime ?? time))
            timeConstant += (desiredResponse - timeConstant) * (1 - exp(-elapsed / 0.12))
        }
        timeConstant = DampedMotion.timeConstant(timeConstant, from: Double(sampleValue),
                                                velocity: sampleVelocity, to: Double(nextTarget))
        direction = nextDirection
        target = nextTarget
        targetChangeTime = time
    }

    /// Evaluates the accepted target's settling trajectory. Future display
    /// queries never extrapolate a new sensor target or change its history.
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
        let state = DampedMotion.response(from: Double(origin), velocity: initialVelocity,
                                          to: Double(target), timeConstant: timeConstant, elapsed: elapsed)
        return (Float(state.value), state.velocity)
    }
}

/// Exact critically damped motion used for lid tracking and programmatic stops.
/// Keep incoming velocity; choose damping that will brake before the destination
/// instead of clipping a moving trajectory when it crosses the target.
enum DampedMotion {
    static func timeConstant(_ proposed: Double, from origin: Double,
                             velocity: Double, to target: Double) -> Double {
        let error = origin - target
        if error * velocity < 0 { return min(proposed, abs(error / velocity)) }
        return proposed
    }

    static func response(from origin: Double, velocity: Double, to target: Double,
                         timeConstant: Double, elapsed: Double) -> (value: Double, velocity: Double) {
        guard elapsed > 0 else { return (origin, velocity) }
        let tau = max(0.000001, timeConstant)
        let decay = exp(-elapsed / tau)
        let coefficient = velocity + (origin - target) / tau
        let value = target + (origin - target + coefficient * elapsed) * decay
        let speed = (velocity - coefficient * elapsed / tau) * decay
        if abs(target - value) < 0.00005 && abs(speed) < 0.003 { return (target, 0) }
        return (value, speed)
    }
}

/// Return the desktop when the effect is disabled during a gesture. Manual
/// reopening never uses this trajectory: it stays on MotionSmoothing through zero.
struct ProgrammaticReturn {
    private var origin = 0.0
    private var initialVelocity = 0.0
    private var timeConstant = 0.060
    private var elapsed = 0.0
    private(set) var velocity = 0.0
    private(set) var active = false

    mutating func begin(from value: Float, velocity: Double) {
        origin = value.isFinite ? max(0, Double(value)) : 0
        initialVelocity = origin > 0 && velocity.isFinite ? velocity : 0
        self.velocity = initialVelocity
        elapsed = 0
        let travelTime = abs(origin) / max(0.01, abs(initialVelocity))
        timeConstant = DampedMotion.timeConstant(min(0.080, max(0.035, travelTime * 0.50)),
                                                from: origin, velocity: initialVelocity, to: 0)
        // Leave room for the unchanged fade and 800 ms cleanup watchdog,
        // including disabling the effect from a deep fold.
        while DampedMotion.response(from: origin, velocity: initialVelocity, to: 0,
                                    timeConstant: timeConstant, elapsed: 0.650).value != 0 {
            timeConstant *= 0.9
        }
        active = origin != 0 || initialVelocity != 0
    }

    mutating func step(elapsed delta: Double) -> Float {
        guard active else { return 0 }
        if delta.isFinite { elapsed += max(0, delta) }
        let state = DampedMotion.response(from: origin, velocity: initialVelocity, to: 0,
                                          timeConstant: timeConstant, elapsed: elapsed)
        velocity = state.velocity
        active = state.value != 0 || state.velocity != 0
        return Float(state.value)
    }
}

/// A bounded quintic handoff that can preserve motion already on screen.
struct HandoffTransition {
    enum Curve { case balanced, pauseRestoration }

    static let duration: Double = 0.100
    static func pauseRestorationDuration(for fold: Float) -> Double {
        min(0.600, 0.340 + sqrt(Double(abs(fold))) * 0.20)
    }
    private var origin: Float = 0
    private var initialVelocity: Double = 0
    private var transitionDuration = Self.duration
    private var elapsed: Double = 0
    private(set) var velocity: Double = 0
    private(set) var active = false
    private var firstFrame = false

    mutating func begin(from value: Float, velocity: Double = 0, duration: Double = Self.duration,
                        holdFirstFrame: Bool = true, curve: Curve = .balanced) {
        origin = value
        initialVelocity = velocity.isFinite ? velocity : 0
        self.velocity = initialVelocity
        transitionDuration = duration.isFinite
            ? min(curve == .pauseRestoration ? 0.650 : 0.300, max(0.060, duration)) : Self.duration
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
        let baseBlend = t * t * t * (t * (t * 6 - 15) + 10)
        let tangentBlend = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
        let baseDerivative = 30 * t * t * (1 - t) * (1 - t)
        // Both curves use balanced acceleration. Pause restoration gets its
        // gentler peak speed from a longer distance-aware duration.
        let blend = baseBlend
        let blendDerivative = baseDerivative
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
