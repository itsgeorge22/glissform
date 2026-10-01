import Foundation

/// Smooths lid readings. Fast, sparse changes carry a short, damped continuation
/// between reports; slow motion stays within the last observed angle.
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
    private var fineMotionStreak = 0
    private var sparseVelocity = 0.0
    private var predictionSlope = 0.0
    private let predictionHorizon = 0.100
    private let maximumPrediction = 6.0 * Double.pi / 180
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
        fineMotionStreak = 0
        sparseVelocity = 0
        predictionSlope = 0
        pendingReversal = nil
        compatibilityTime = sampleTime ?? 0
        lastPresentationTime = nil
    }

    mutating func ingest(target nextTarget: Float, at time: Double) {
        guard nextTarget.isFinite, time.isFinite,
              sampleTime.map({ time >= $0 }) ?? true else { return }
        if let sampleTime {
            if time - sampleTime > 0.100 {
                pendingReversal = nil
                fineMotionStreak = 0
            }
            let state = response(from: sampleValue, velocity: sampleVelocity,
                                 elapsed: time - sampleTime)
            sampleValue = state.value
            sampleVelocity = state.velocity
        }
        sampleTime = time
        let change = nextTarget - target
        guard change != 0 else {
            pendingReversal = nil
            if predictionSlope != 0 && time - (targetChangeTime ?? time) >= 0.080 {
                predictionSlope = 0
                sparseVelocity = 0
                timeConstant = 0.035
            }
            return
        }
        guard nextTarget == 0 || abs(change) >= noiseFloor else {
            // Fractional HID reports fluctuate by a few hundredths of a degree
            // even when the lid is still. Keep the last meaningful target.
            if predictionSlope != 0 && time - (targetChangeTime ?? time) >= 0.080 {
                predictionSlope = 0
                sparseVelocity = 0
                timeConstant = 0.035
            }
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
        let elapsedSinceChange = time - (targetChangeTime ?? time)
        let changeDegrees = Double(abs(change)) * 180 / .pi
        let sparse = nextTarget != 0 && changeDegrees >= 2 && elapsedSinceChange >= 0.065
            && elapsedSinceChange <= 0.160
        if sparse {
            let measuredVelocity = Double(change) / elapsedSinceChange
            sparseVelocity = reversing || sparseVelocity == 0 ? measuredVelocity
                : 0.6 * measuredVelocity + 0.4 * sparseVelocity
            // Half of the measured speed fills part of the ~100 ms gap. A
            // 45 ms damped response absorbs report corrections and keeps
            // abrupt-stop overshoot small even at roughly 100 degrees/s.
            predictionSlope = max(-maximumPrediction / predictionHorizon,
                                  min(maximumPrediction / predictionHorizon,
                                      0.5 * sparseVelocity))
            predictionSlope = max(predictionSlope, -Double(nextTarget) / predictionHorizon)
        } else {
            sparseVelocity = 0
            predictionSlope = 0
        }
        // Several timely sub-degree reports establish real fine motion. A
        // single fractional wobble, a whole-degree fallback, or a reversal
        // must keep the original response rather than suddenly accelerating.
        if !reversing && direction != 0 && changeDegrees < 0.75
            && elapsedSinceChange >= 0.010 && elapsedSinceChange <= 0.085 {
            fineMotionStreak = min(4, fineMotionStreak + 1)
        } else {
            fineMotionStreak = changeDegrees < 0.75 && !reversing ? 1 : 0
        }
        // Fractional readings can be much smaller than one degree. Preserve
        // their measured cadence, but cap the response to a quarter-degree
        // step so very slow motion does not acquire excessive lag.
        let degrees = max(0.25, changeDegrees)
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
        let baselineResponse = min(0.118, max(0.024, movingResponse, degreeInterval * 0.43))
        let fineConfidence = min(1, Double(max(0, fineMotionStreak - 1)) / 3)
        let desiredResponse = baselineResponse + (min(baselineResponse, 0.035) - baselineResponse) * fineConfidence
        if direction == 0 {
            timeConstant = abs(change) > 0.1 ? 0.0125 : 0.035
        } else if reversing {
            // Brake the existing momentum instead of deleting it. A real
            // reversal remains responsive without the old 12.5 ms kick.
            timeConstant = min(timeConstant, 0.045)
        } else {
            let responseTime = fineConfidence > 0 ? 0.060 : 0.12
            timeConstant += (desiredResponse - timeConstant) * (1 - exp(-elapsedSinceChange / responseTime))
        }
        if sparse {
            timeConstant = reversing ? 0.035 : 0.045
        } else {
            timeConstant = DampedMotion.timeConstant(timeConstant, from: Double(sampleValue),
                                                    velocity: sampleVelocity, to: Double(nextTarget))
        }
        direction = nextDirection
        target = nextTarget
        targetChangeTime = time
    }

    /// Evaluates the sample-anchored trajectory. Future display queries do
    /// not change sensor history or the estimated velocity.
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
        if predictionSlope != 0, let sampleTime, let targetChangeTime {
            let age = max(0, sampleTime - targetChangeTime)
            let ramp = min(elapsed, max(0, predictionHorizon - age))
            if ramp > 0 {
                let goal = Double(target) + predictionSlope * age
                let state = DampedMotion.rampResponse(from: Double(origin), velocity: initialVelocity,
                                                      to: goal, slope: predictionSlope,
                                                      timeConstant: timeConstant, elapsed: ramp)
                if ramp == elapsed { return (Float(state.value), state.velocity) }
                let held = Double(target) + predictionSlope * predictionHorizon
                let finish = DampedMotion.response(from: state.value, velocity: state.velocity,
                                                   to: held, timeConstant: timeConstant,
                                                   elapsed: elapsed - ramp)
                return (Float(finish.value), finish.velocity)
            }
            let held = Double(target) + predictionSlope * predictionHorizon
            let state = DampedMotion.response(from: Double(origin), velocity: initialVelocity,
                                              to: held, timeConstant: timeConstant, elapsed: elapsed)
            return (Float(state.value), state.velocity)
        }
        let state = DampedMotion.response(from: Double(origin), velocity: initialVelocity,
                                          to: Double(target), timeConstant: timeConstant, elapsed: elapsed)
        return (Float(state.value), state.velocity)
    }
}

/// Exact critically damped motion used for lid tracking and programmatic stops.
/// Keep incoming velocity; choose damping that will brake before the destination
/// instead of clipping a moving trajectory when it crosses the target.
enum DampedMotion {
    /// Exact critically damped response to a target moving at a fixed speed.
    static func rampResponse(from origin: Double, velocity: Double, to target: Double,
                             slope: Double, timeConstant: Double,
                             elapsed: Double) -> (value: Double, velocity: Double) {
        guard elapsed > 0 else { return (origin, velocity) }
        let tau = max(0.000001, timeConstant)
        let decay = exp(-elapsed / tau)
        let offset = origin - target + 2 * tau * slope
        let coefficient = velocity - slope + offset / tau
        let position = target + slope * (elapsed - 2 * tau)
            + (offset + coefficient * elapsed) * decay
        let speed = slope + (coefficient - (offset + coefficient * elapsed) / tau) * decay
        return (position, speed)
    }

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

/// Return the desktop when the effect is disabled during a gesture. Reopening
/// follows MotionSmoothing until its final assisted handoff or physical endpoint.
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

/// Carries visible opening momentum into the assisted finish. An older sensor
/// estimate cannot lower the cruising speed; bounded acceleration joins it softly.
struct OpeningContinuation {
    private static let speedBlendDuration = 0.080
    private var origin: Double = 0
    private var initialSpeed: Double = 0
    private var initialAcceleration: Double = 0
    private var measuredSpeed: Double = 0
    private var rampDuration: Double = 0
    private var rampDistance: Double = 0
    private var cruiseDuration: Double = 0
    private var terminalDistance: Double = 0
    private var terminalSpeed: Double = 0
    private var terminalDuration: Double = 0
    private var elapsed: Double = 0
    private(set) var velocity: Double = 0
    private(set) var active = false

    var completionFraction: Float {
        let duration = rampDuration + cruiseDuration + terminalDuration
        return duration > 0 ? Float(min(1, elapsed / duration)) : 1
    }

    mutating func begin(from fold: Float, velocity displayedVelocity: Double,
                        acceleration displayedAcceleration: Double = 0, observedSpeed: Double) {
        origin = fold.isFinite ? max(0, Double(fold)) : 0
        initialSpeed = displayedVelocity.isFinite ? max(0, -displayedVelocity) : 0
        let sensorSpeed = observedSpeed.isFinite ? max(1, observedSpeed) : 1
        measuredSpeed = max(initialSpeed, sensorSpeed * .pi / 180)
        // Display-to-display acceleration can include sensor quantization. Carry
        // its sign, but bound the extra momentum to 25% of the entry/measured
        // pace, and a pre-existing slowdown to a small dip before cruising.
        let acceleration = displayedAcceleration.isFinite ? -displayedAcceleration : 0
        initialAcceleration = min(0.5 * measuredSpeed / Self.speedBlendDuration,
                                  max(-0.25 * initialSpeed / Self.speedBlendDuration, acceleration))
        terminalDistance = min(origin * 0.15, 1.5 * .pi / 180)
        let travelDistance = origin - terminalDistance
        rampDuration = Self.speedBlendDuration
        if blendDistance(duration: rampDuration) > travelDistance {
            // Fit the entire acceleration-aware blend into a shallow fold;
            // truncating it would introduce another acceleration discontinuity.
            var low = 0.0, high = rampDuration
            for _ in 0..<40 {
                let middle = (low + high) * 0.5
                if blendDistance(duration: middle) < travelDistance { low = middle }
                else { high = middle }
            }
            rampDuration = (low + high) * 0.5
        }
        terminalSpeed = cruisingSpeed(duration: rampDuration)
        rampDistance = blendDistance(duration: rampDuration)
        cruiseDuration = max(0, travelDistance - rampDistance) / terminalSpeed
        terminalDuration = terminalDistance > 0 ? 2 * terminalDistance / terminalSpeed : 0
        elapsed = 0
        velocity = -initialSpeed
        active = origin > 0
    }

    private func cruisingSpeed(duration: Double) -> Double {
        // This also keeps a positive entry acceleration monotonic all the way
        // into cruising instead of accelerating and then braking in the blend.
        max(measuredSpeed, initialSpeed + 0.5 * max(0, initialAcceleration) * duration)
    }

    private func blendDistance(duration: Double) -> Double {
        duration * (0.5 * (initialSpeed + cruisingSpeed(duration: duration))
                    + 0.1 * initialAcceleration * duration)
    }

    mutating func step(elapsed delta: Double) -> Float {
        guard active else { return 0 }
        if delta.isFinite { elapsed += max(0, delta) }
        if elapsed < rampDuration {
            let t = elapsed / rampDuration
            let blend = pow(t, 3) * (10 - 15 * t + 6 * t * t)
            let tangent = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
            let difference = terminalSpeed - initialSpeed
            velocity = -(initialSpeed + difference * blend
                         + initialAcceleration * rampDuration * tangent)
            let distance = rampDuration * (initialSpeed * t
                + difference * pow(t, 4) * (2.5 - 3 * t + t * t)
                + initialAcceleration * rampDuration
                    * (0.5 * t * t - 1.5 * pow(t, 4) + 1.6 * pow(t, 5) - 0.5 * pow(t, 6)))
            return Float(max(0, origin - distance))
        }
        if elapsed < rampDuration + cruiseDuration {
            velocity = -terminalSpeed
            return Float(max(0, origin - rampDistance - terminalSpeed * (elapsed - rampDuration)))
        }
        let fraction = terminalDuration > 0
            ? min(1, (elapsed - rampDuration - cruiseDuration) / terminalDuration) : 1
        if fraction == 1 {
            active = false
            velocity = 0
            return 0
        }
        // Keep the gentle landing with continuous speed and acceleration.
        let remaining = 1 - fraction
        velocity = -terminalSpeed * pow(remaining, 3) * (1 + 3 * fraction + 6 * fraction * fraction)
        return Float(terminalDistance * pow(remaining, 4) * (1 + 2 * fraction + 2 * fraction * fraction))
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
        let maximumDuration: Double
        switch curve {
        case .balanced: maximumDuration = 0.300
        case .pauseRestoration: maximumDuration = 0.650
        }
        transitionDuration = duration.isFinite
            ? min(maximumDuration, max(0.060, duration)) : Self.duration
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
