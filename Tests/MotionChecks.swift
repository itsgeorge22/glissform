import Foundation

@main struct MotionChecks {
    static func main() {
        var displayedLid = LidAnglePresentation()
        precondition(displayedLid.ingest(100, at: 0) == 100)
        for (reading, time) in [(101.0, 0.05), (100.0, 0.12), (101.0, 0.20), (100.0, 0.28)] {
            precondition(displayedLid.ingest(reading, at: time) == 100,
                         "A one-degree boundary fluctuation must not flicker in Settings")
        }
        precondition(displayedLid.ingest(101, at: 0.35) == 100)
        precondition(displayedLid.ingest(101, at: 0.45) == 100)
        precondition(displayedLid.ingest(101, at: 0.61) == 101,
                     "A sustained one-degree change must appear after 250 ms")
        precondition(displayedLid.ingest(102, at: 0.70) == 101)
        precondition(displayedLid.ingest(102, at: 0.85) == 101)
        precondition(displayedLid.ingest(102, at: 0.96) == 102,
                     "Slow movement must advance through consecutive one-degree readings")
        precondition(displayedLid.ingest(104, at: 1.0) == 104,
                     "A two-degree movement must appear immediately")
        var gappedDisplay = LidAnglePresentation()
        precondition(gappedDisplay.ingest(100, at: 0) == 100)
        precondition(gappedDisplay.ingest(101, at: 0.1) == 100)
        precondition(gappedDisplay.ingest(101, at: 0.5) == 100,
                     "A gap in sensor samples must restart the display wait")
        precondition(gappedDisplay.ingest(101, at: 0.65) == 100)
        precondition(gappedDisplay.ingest(101, at: 0.76) == 101)
        displayedLid.reset()
        precondition(displayedLid.angle == nil && displayedLid.ingest(95, at: 4) == 95,
                     "A new sensor connection must show its first reading immediately")
        print("PASS: Settings-only lid angle display resists one-degree flicker and follows larger motion")

        var smooth = MotionSmoothing()
        var last: Float = 0
        for _ in 0..<6 {
            let next = smooth.step(toward: 1, elapsed: 0.010)
            precondition(next > last && next <= 1, "Settling must never overshoot")
            last = next
        }
        precondition(last > 0.95, "Stop must settle at least 95% within 60 ms")
        let reversed = smooth.step(toward: 0, elapsed: 1.0 / 60)
        precondition(reversed < last, "Reversal responds on the very next frame")
        var fastFrames = MotionSmoothing()
        for _ in 0..<12 { _ = fastFrames.step(toward: 1, elapsed: 0.005) }
        precondition(abs(fastFrames.value - last) < 0.00001, "Settling must be frame-rate independent")
        for _ in 0..<60 { _ = smooth.step(toward: 0, elapsed: 1.0 / 60) }
        precondition(smooth.value == 0, "Settling must finish so idle rendering can pause")
        smooth.reset()
        precondition(smooth.value == 0)
        print("PASS: soft stop, immediate reversal, no overshoot, frame-rate independence, idle settling")
        // Two display frames between 30 Hz sensor reports must both advance.
        var betweenReadings = MotionSmoothing()
        let firstFrame = betweenReadings.step(toward: 0.1, elapsed: 1.0 / 60)
        let secondFrame = betweenReadings.step(toward: 0.1, elapsed: 1.0 / 60)
        precondition(secondFrame > firstFrame && secondFrame < 0.1,
                     "Animation must keep settling between sensor events")
        print("PASS: intermediate display frames between lid readings")
        // Slow closure: one whole-degree report every 200 ms. The old 20 ms
        // exponential filter moved 56% of each step on its first frame, then froze.
        var slow = MotionSmoothing()
        let degree = Float(Double.pi / 180)
        for step in 1...8 {
            let target = Float(step) * degree
            let before = slow.value
            let first = slow.step(toward: target, elapsed: 1.0 / 60)
            precondition(first - before < degree * 0.25, "No abrupt jump on the degree boundary")
            var previous = first
            for frame in 1..<12 {
                let next = slow.step(toward: target, elapsed: 1.0 / 60)
                precondition(next >= previous && next <= target, "Slow motion must not overshoot")
                if frame == 11 && step > 1 {
                    precondition(next > previous, "Keep moving between sparse degree readings")
                }
                previous = next
            }
        }
        let beforeReverse = slow.value
        precondition(slow.step(toward: 6 * degree, elapsed: 1.0 / 60) < beforeReverse,
                     "Small-step smoothing must still reverse on the next frame")
        for _ in 0..<90 { _ = slow.step(toward: 6 * degree, elapsed: 1.0 / 60) }
        precondition(slow.value == 6 * degree, "Stopped sensor must settle exactly, without invented motion")
        print("PASS: slow whole-degree staircase, gentle boundaries, immediate reversal, finite settling")
        // Replay quantized 30 Hz input on independent 60/120 Hz frame clocks.
        // Measure against the continuous physical motion, not the filter target.
        let rippleLimits: [Double: Double] = [2: 0.62, 5: 0.28, 7: 0.33, 12: 0.24,
                                             20: 0.14, 30: 0.04, 45: 0.15, 60: 0.09, 90: 0.14]
        for speed in rippleLimits.keys.sorted() {
            for fps in [60.0, 120.0] {
                var tracking = MotionSmoothing()
                var totalError = 0.0
                var samples = 0
                var lastAngle = 0.0
                var speedErrors: [Double] = []
                for frame in 1...Int(3 * fps) {
                    let time = Double(frame) / fps
                    let sensorTime = floor(time * 30 + 0.000001) / 30
                    let reported = Float((sensorTime * speed).rounded() * .pi / 180)
                    let rendered = tracking.step(toward: reported, elapsed: 1 / fps)
                    precondition(rendered <= reported + 0.000001, "Never predict an unreported angle")
                    let angle = Double(rendered) * 180 / .pi
                    if time > 0.5 {
                        totalError += abs(angle - time * speed)
                        samples += 1
                    }
                    if time > 1 { speedErrors.append(pow((angle - lastAngle) * fps - speed, 2)) }
                    lastAngle = angle
                }
                let meanDelay = totalError / Double(samples) / speed
                let ripple = sqrt(speedErrors.reduce(0, +) / Double(speedErrors.count)) / speed
                precondition(ripple < rippleLimits[speed]!,
                             "Speed ripple must stay bounded at \(speed) degrees/s, \(fps) Hz: \(ripple)")
                precondition(meanDelay < (speed <= 7 ? 0.240 : 0.100),
                             "Tracking delay must stay bounded at \(speed) degrees/s, \(fps) Hz: \(meanDelay)")
                print(String(format: "PASS: %.0f°/s at %.0f Hz, tracking error %.1f ms, relative speed ripple %.3f", speed, fps, meanDelay * 1000, ripple))
            }
        }
        // Source timing must remain independent of the display clock and its
        // phase. Poll at both rates, including sub-degree repeated readings.
        for pollRate in [30.0, 60.0] {
            for fps in [60.0, 120.0] {
                for phaseFraction in [0.0, 0.17, 0.43, 0.79] {
                    for speed in [2.0, 5.0, 30.0, 60.0, 90.0] {
                        var tracking = MotionSmoothing()
                        tracking.reset(at: 0)
                        var sample = 0
                        var latest: Float = 0
                        var error = 0.0
                        var count = 0
                        for frame in 1...Int(3 * fps) {
                            let time = Double(frame) / fps
                            while (Double(sample) + phaseFraction) / pollRate <= time + 0.0000001 {
                                let acquiredAt = (Double(sample) + phaseFraction) / pollRate
                                latest = Float((acquiredAt * speed).rounded() * .pi / 180)
                                tracking.ingest(target: latest, at: acquiredAt)
                                sample += 1
                            }
                            let rendered = tracking.step(at: time)
                            precondition(rendered >= 0 && rendered <= latest + 0.000001,
                                         "Presentation queries must not predict unreported motion")
                            if time > 1 {
                                error += abs(Double(rendered) * 180 / .pi - time * speed) / speed
                                count += 1
                            }
                        }
                        precondition(error / Double(count) < (speed <= 5 ? 0.270 : 0.140),
                                     "Acquisition-timed tracking must remain bounded across clock phases")
                    }
                }
            }
        }
        print("PASS: acquisition-timed 30/60 Hz inputs across independent 60/120 Hz display phases")

        // Render ahead frequently on one copy and only after delayed delivery on
        // the other. Once the same observations have arrived, both must describe
        // the same motion; callback frequency cannot alter cadence or momentum.
        var immediate = MotionSmoothing()
        var delayed = MotionSmoothing()
        immediate.reset(at: 0)
        delayed.reset(at: 0)
        var pending: [(Float, Double)] = []
        for sample in 1...180 {
            let acquiredAt = Double(sample) / 60
            let angle = sample <= 60 ? Double(sample) * 0.4
                : sample <= 100 ? 24 : max(0, 24 - Double(sample - 100) * 0.3)
            let target = Float(angle.rounded() * .pi / 180)
            immediate.ingest(target: target, at: acquiredAt)
            _ = immediate.step(at: acquiredAt + 0.014)
            pending.append((target, acquiredAt))
            if sample.isMultiple(of: 5) {
                for (value, time) in pending { delayed.ingest(target: value, at: time) }
                pending.removeAll()
                let time = acquiredAt + 0.014
                precondition(abs(immediate.step(at: time) - delayed.step(at: time)) < 0.000001,
                             "Delayed delivery must not rewrite source cadence")
                precondition(abs(immediate.velocity - delayed.velocity) < 0.000001,
                             "Rendering ahead must not change sample-anchored velocity")
            }
        }
        let beforeStale = immediate
        immediate.ingest(target: 1, at: 0.1)
        immediate.ingest(target: .nan, at: 4)
        var unchanged = beforeStale
        precondition(immediate.step(at: 3.1) == unchanged.step(at: 3.1), "Reject stale and invalid input")
        let beforeBackward = immediate.value
        precondition(immediate.step(at: 2.0) == beforeBackward, "Reject backward presentation time")
        precondition(immediate.step(at: 5) == 0 && immediate.velocity == 0,
                     "A stopped source must settle without perpetual extrapolation")
        var timestampedReverse = MotionSmoothing()
        timestampedReverse.ingest(target: 0.5, at: 0)
        let beforeTimestampedReverse = timestampedReverse.step(at: 0.1)
        timestampedReverse.ingest(target: 0.1, at: 0.1)
        precondition(timestampedReverse.step(at: 0.116) < beforeTimestampedReverse,
                     "Timestamped reversal must respond on the next display")
        print("PASS: delayed delivery, future presentation queries, stops, reversals and stale timestamps")

        // Full physical rotation, including reference angles above 90 degrees.
        for reference in [20.0, 85, 100, 130] {
            var previousFold: Float = -1
            for angle in stride(from: reference, through: 4, by: -1) {
                let fold = ScreenProjection.foldRadians(lidAngle: angle, referenceAngle: reference)
                precondition(abs(Double(fold) * 180 / .pi - (reference - angle)) < 0.00002,
                             "Projection must compensate the full physical angle")
                precondition(fold > previousFold, "Projection must not freeze late in closure")
                previousFold = fold
            }
        }
        print("PASS: one-to-one physical rotation throughout 20–130 degree trigger range")
        var handoff = HandoffTransition()
        handoff.begin(from: 0)
        precondition(handoff.step(toward: 1, elapsed: 0) == 0, "Entrance starts at the unchanged image")
        precondition(handoff.step(toward: 1, elapsed: 0.010) < 0.01, "Entrance starts gently")
        let middle = handoff.step(toward: 1, elapsed: 0.040)
        precondition(abs(middle - 0.5) < 0.001)
        handoff.begin(from: middle)
        precondition(handoff.step(toward: 0, elapsed: 0) == middle, "Interrupted entrance returns from its displayed angle")
        precondition(handoff.step(toward: 0, elapsed: 0.100) == 0 && !handoff.active,
                     "Exit reaches an exact flat image before releasing the snapshot")
        handoff.begin(from: 0.2)
        precondition(handoff.step(toward: 0.7, elapsed: 0) == 0.2, "Reclosing during exit must not jump")
        handoff.begin(from: 0)
        precondition(handoff.step(toward: 1, elapsed: 0.5) == 0,
                     "Even a late first display frame must start at exactly zero effect")
        precondition(handoff.step(toward: 1, elapsed: 0.010) < 0.01)
        print("PASS: exact zero first frame, gentle entry and exit, interrupted entrance, reclose continuity")
        // Ordinary return inherits its feasible onscreen speed. A prepared
        // frame needs no extra one-frame hold before movement begins.
        var movingReturn = HandoffTransition()
        movingReturn.begin(from: 0.4, velocity: -1.5, duration: 0.180, holdFirstFrame: false)
        let tinyStep = movingReturn.step(toward: 0, elapsed: 0.00001)
        precondition(abs(Double(tinyStep - 0.4) / 0.00001 + 1.5) < 0.005,
                     "Return must inherit a feasible starting velocity")
        var lastReturn: Float = tinyStep
        for _ in 0..<180 {
            let next = movingReturn.step(toward: 0, elapsed: 0.001)
            precondition(next >= 0 && next <= lastReturn, "Return must not overshoot or move backwards")
            lastReturn = next
        }
        precondition(lastReturn == 0 && movingReturn.velocity == 0 && !movingReturn.active,
                     "Return ends flat and at rest")
        for startingVelocity in [-100.0, 100.0] {
            var bounded = HandoffTransition()
            bounded.begin(from: 0.4, velocity: startingVelocity, duration: 0.200, holdFirstFrame: false)
            var previous: Float = 0.4
            for _ in 0..<21 {
                let value = bounded.step(toward: 0, elapsed: 0.010)
                precondition(value >= 0 && value <= previous,
                             "Impossible boundary velocities must be bounded without overshoot")
                previous = value
            }
        }
        var movingEntrance = HandoffTransition()
        movingEntrance.begin(from: 0, duration: 0.100, holdFirstFrame: false)
        for frame in 1...100 {
            let t = Double(frame) * 0.001
            _ = movingEntrance.step(toward: Float(0.3 + 0.4 * t), velocity: 0.4, elapsed: 0.001)
        }
        precondition(!movingEntrance.active && abs(movingEntrance.velocity - 0.4) < 0.000001,
                     "Entrance must join the moving target with its velocity")
        var deepReturn = HandoffTransition()
        deepReturn.begin(from: 1, duration: 0.240, holdFirstFrame: false)
        _ = deepReturn.step(toward: 0, elapsed: 0.100)
        precondition(deepReturn.active, "Deep pause restoration can use a longer bounded return")
        precondition(deepReturn.step(toward: 0, elapsed: 0.140) == 0 && !deepReturn.active)
        print("PASS: boundary velocity, prepared-frame movement, bounded returns and moving-target join")

        var pauseReturn = HandoffTransition()
        pauseReturn.begin(from: 1, duration: 0.400, holdFirstFrame: false, curve: .pauseRestoration)
        var previousPauseValue: Float = 1
        for frame in 1...40 {
            let value = pauseReturn.step(toward: 0, elapsed: 0.010)
            precondition(value >= 0 && value <= previousPauseValue,
                         "Pause restoration must settle without reversing or bouncing")
            if frame == 20 {
                precondition(value < 0.45 && value > 0.25,
                             "Pause restoration should move decisively before its soft landing")
            }
            previousPauseValue = value
        }
        precondition(previousPauseValue == 0 && pauseReturn.velocity == 0 && !pauseReturn.active,
                     "Pause restoration must finish exactly flat and at rest")
        print("PASS: eased pause restoration, monotonic return and exact flat finish")

        // Pause-to-resume uses a monotonic sample clock, not time since capture.
        func pausingMotion(duration: Double = 2, enabled: Bool = true) -> ClosingMotion {
            var state = ClosingMotion()
            state.startAngle = 95
            state.resumeAfterPause = enabled
            state.pauseDuration = duration
            _ = state.update(angle: 100, time: -0.05)
            return state
        }
        for duration in [0.5, 2.0, 10.0] {
            var state = pausingMotion(duration: duration)
            for frame in 0..<Int(duration * 20) {
                _ = state.update(angle: 80, time: Double(frame) / 20)
                precondition(state.active && !state.desktopResumed, "Do not resume before the selected pause")
            }
            precondition(state.update(angle: 80, time: duration + 0.000001) == 0 && state.desktopResumed)
            for angle in [80.0, 70, 90, 95, 80] {
                precondition(state.update(angle: angle, time: duration + 1) == 0 && !state.active,
                             "Stay usable below or exactly at the threshold after restoring")
            }
            _ = state.update(angle: 96, time: duration + 1.1)
            precondition(!state.desktopResumed)
            precondition(state.update(angle: 80, time: duration + 1.2) > 0 && state.active,
                         "Opening above the threshold must arm a new gesture")
            state.reset()
            precondition(state.update(angle: 80, time: duration + 1.3) == 0 && !state.active)
        }
        var disabledPause = pausingMotion(enabled: false)
        var movingPause = pausingMotion(duration: 0.5)
        var jitterPause = pausingMotion(duration: 0.5)
        for frame in 0...240 {
            _ = disabledPause.update(angle: 80, time: Double(frame) / 20)
            precondition(disabledPause.active, "Default off must preserve the effect during pauses")
            _ = movingPause.update(angle: 90 - Double(frame) * 0.25, time: Double(frame) / 20)
            precondition(movingPause.active, "Slow continuous drift must reset the pause")
            _ = jitterPause.update(angle: frame.isMultiple(of: 2) ? 80 : 81, time: Double(frame) / 20)
        }
        precondition(jitterPause.desktopResumed, "One-degree sensor chatter must not prevent restoration")
        var interruptedPause = pausingMotion(duration: 0.5)
        for frame in 0...8 { _ = interruptedPause.update(angle: 80, time: Double(frame) / 20) }
        _ = interruptedPause.update(angle: 82, time: 0.45)
        _ = interruptedPause.update(angle: 82, time: 0.6)
        precondition(interruptedPause.active, "Meaningful reopening resets the timer")
        _ = interruptedPause.update(angle: 82, time: 5)
        precondition(interruptedPause.active, "Missing sensor reports are not proof of a pause")
        _ = interruptedPause.update(angle: .nan, time: 5.1)
        _ = interruptedPause.update(angle: 82, time: 5.2)
        precondition(interruptedPause.active, "Invalid reports reset pause tracking")
        interruptedPause.pauseDuration = 2
        _ = interruptedPause.update(angle: 82, time: 5.3)
        precondition(interruptedPause.active, "Changing the delay starts a fresh wait")
        print("PASS: pause durations, default off, jitter, slow movement, reversal, sensor gaps, restoration latch and rearming")
        var motion = ClosingMotion()
        for angle in [110.0, 109, 110, 111, 110] {
            precondition(motion.update(angle: angle) == 0, "Ordinary viewing must remain clear")
        }
        var previous: Float = 0
        precondition(motion.activationAngle == 111, "Reference plane must use the actual resting angle")
        precondition(motion.update(angle: 108) > 0, "Projection starts near the resting angle, not at 85 degrees")
        for angle in stride(from: 84.0, through: 4, by: -2) {
            let progress = motion.update(angle: angle)
            precondition(progress >= previous, "Closing progress must be monotonic")
            previous = progress
        }
        precondition(abs(previous - 1) < 0.001, "Closing endpoint")
        for angle in stride(from: 6.0, through: 108, by: 2) {
            let progress = motion.update(angle: angle)
            precondition(progress < previous && progress > 0, "Reopening must smoothly reverse")
            precondition(motion.active && motion.activationAngle == 111, "Keep the same gesture and plane")
            previous = progress
        }
        let halfway = motion.update(angle: 60)
        precondition(motion.update(angle: 40) > halfway)
        precondition(motion.update(angle: 60) == halfway, "Same angle produces identical effect in both directions")
        precondition(motion.update(angle: 110) > 0 && motion.active, "Do not discard the screenshot before the starting angle")
        precondition(motion.update(angle: 111) == 0 && !motion.active, "Reaching the starting angle ends the gesture")
        precondition(motion.update(angle: 110) == 0 && !motion.active, "Idle deadband prevents repeated screenshots")
        precondition(motion.update(angle: 60) > 0 && motion.active, "Second closure starts a fresh gesture")
        motion.reset()
        precondition(motion.update(angle: 45) == 0, "No overlay on launch with low lid")
        precondition(motion.update(angle: 46) == 0)
        precondition(motion.update(angle: 20) > 0)
        motion.reset()
        precondition(motion.update(angle: 20) == 0, "Reset prevents wake overlay")
        precondition(motion.update(angle: .nan) == 0)
        precondition(motion.update(angle: -1) == 0)
        var threshold = ClosingMotion()
        threshold.startAngle = 90
        precondition(threshold.update(angle: 70) == 0 && !threshold.active, "Starting below the threshold must stay clear")
        precondition(threshold.update(angle: 85) == 0, "Opening below threshold must stay clear")
        precondition(threshold.update(angle: 100) == 0)
        precondition(threshold.update(angle: 90) == 0)
        let partial = threshold.update(angle: 80)
        precondition(partial > 0 && threshold.activationAngle == 90)
        precondition(threshold.update(angle: 60) > partial)
        precondition(threshold.update(angle: 80) == partial, "Reverse around the selected angle")
        precondition(threshold.update(angle: 90) == 0 && !threshold.active)
        threshold.reset()
        threshold.startAngle = 50
        precondition(threshold.update(angle: 60) == 0)
        precondition(threshold.update(angle: 51) == 0)
        precondition(threshold.update(angle: 49) > 0 && threshold.activationAngle == 50)
        print("PASS: selected threshold, below-threshold startup, threshold reversal, changed threshold")

        var automatic = ClosingMotion()
        automatic.startAngle = 95
        automatic.automaticStartAngle = true
        _ = automatic.update(angle: 110, time: 0)
        _ = automatic.update(angle: 111, time: 1)
        precondition(automatic.learnedStartAngle == nil, "A short or jittering rest must retain the manual fallback")
        for frame in 21...62 { _ = automatic.update(angle: 110, time: Double(frame) / 20) }
        precondition(automatic.learnedStartAngle == 109 && automatic.effectiveStartAngle == 109,
                     "A two-second open-lid rest must start one degree below the held angle")
        precondition(automatic.update(angle: 109, time: 3.15) == 0 && !automatic.active)
        precondition(automatic.update(angle: 108, time: 3.17) > 0 && automatic.activationAngle == 109)
        automatic.startAngle = 120
        precondition(automatic.update(angle: 94, time: 3.2) > 0 && automatic.activationAngle == 109,
                     "Editing Begin at must not move an automatically anchored gesture")
        precondition(automatic.update(angle: 109, time: 3.25) == 0 && !automatic.active)
        _ = automatic.update(angle: 100, time: 3.3)
        precondition(automatic.active && automatic.activationAngle == 109,
                     "Crossing the custom angle must not replace the learned angle")
        automatic.reset()
        precondition(automatic.learnedStartAngle == 109 && automatic.effectiveStartAngle == 109,
                     "A lifecycle reset must preserve the learned reference")
        precondition(automatic.beginOpening(angle: 30, time: 3.35) > 0 && automatic.activationAngle == 109,
                     "Wake opening must use the closing reference")
        automatic.automaticStartAngle = false
        precondition(automatic.learnedStartAngle == nil && automatic.effectiveStartAngle == 120,
                     "Turning automatic selection off must restore the manual angle")

        var lowRest = ClosingMotion()
        lowRest.startAngle = 95
        lowRest.automaticStartAngle = true
        for frame in 0...40 { _ = lowRest.update(angle: 80, time: Double(frame) / 20) }
        precondition(lowRest.learnedStartAngle == 79 && !lowRest.active,
                     "A stable opening below the manual fallback may become the start angle")
        precondition(lowRest.update(angle: 79, time: 2.05) == 0 && !lowRest.active)
        precondition(lowRest.update(angle: 78, time: 2.1) > 0 && lowRest.activationAngle == 79)

        var gaps = ClosingMotion()
        gaps.startAngle = 95
        gaps.automaticStartAngle = true
        _ = gaps.update(angle: 110, time: 0)
        _ = gaps.update(angle: 110, time: 2.1)
        precondition(gaps.learnedStartAngle == nil, "Missing sensor samples cannot establish a rest")
        _ = gaps.update(angle: .nan, time: 2.15)
        for frame in 44...85 { _ = gaps.update(angle: 110, time: Double(frame) / 20) }
        precondition(gaps.learnedStartAngle == 109, "Fresh samples can learn after an interruption")

        var jitter = ClosingMotion()
        jitter.startAngle = 95
        jitter.automaticStartAngle = true
        for frame in 0...40 {
            _ = jitter.update(angle: frame.isMultiple(of: 2) ? 110 : 111,
                              time: Double(frame) / 20)
        }
        precondition(jitter.learnedStartAngle == 109,
                     "One-degree sensor chatter must not prevent learning")
        for frame in 41...90 {
            _ = jitter.update(angle: frame.isMultiple(of: 2) ? 110 : 111,
                              time: Double(frame) / 20)
        }
        precondition(jitter.learnedStartAngle == 109,
                     "One-degree sensor chatter must not repeatedly move the learned threshold")
        var unsupported = ClosingMotion()
        unsupported.startAngle = 95
        unsupported.automaticStartAngle = true
        for frame in 0...40 { _ = unsupported.update(angle: 140, time: Double(frame) / 20) }
        precondition(unsupported.learnedStartAngle == nil && unsupported.effectiveStartAngle == 95,
                     "Out-of-range rests must leave the manual fallback in control")

        var restored = ClosingMotion()
        restored.startAngle = 95
        restored.automaticStartAngle = true
        restored.resumeAfterPause = true
        for frame in 0...40 { _ = restored.update(angle: 110, time: Double(frame) / 20) }
        _ = restored.update(angle: 80, time: 2.05)
        for frame in 42...82 { _ = restored.update(angle: 80, time: Double(frame) / 20) }
        precondition(restored.desktopResumed && restored.learnedStartAngle == 79
                     && restored.activationAngle == 109,
                     "An active pause restoration must adopt its new resting angle")
        for frame in 83...125 { _ = restored.update(angle: 80, time: Double(frame) / 20) }
        precondition(!restored.active && restored.desktopResumed && restored.effectiveStartAngle == 79,
                     "A learned pause angle must not restart the effect while still")
        precondition(restored.update(angle: 79, time: 6.27) == 0 && restored.desktopResumed,
                     "Movement below the held angle must not release the pause latch")
        _ = restored.update(angle: 81, time: 6.3)
        precondition(restored.update(angle: 78, time: 6.35) > 0 && restored.activationAngle == 79,
                     "A fresh close after reopening must use the paused angle")
        var noRestore = ClosingMotion()
        noRestore.startAngle = 95
        noRestore.automaticStartAngle = true
        for frame in 0...40 { _ = noRestore.update(angle: 110, time: Double(frame) / 20) }
        for frame in 41...95 { _ = noRestore.update(angle: 80, time: Double(frame) / 20) }
        precondition(noRestore.active && noRestore.learnedStartAngle == 109,
                     "Automatic selection must respect the separate pause-restoration toggle")
        print("PASS: automatic rest learning, manual fallback, gesture lock, wake reference, sample gaps and pause latch")
        print("PASS: ordinary angles, closing progression, reversal, repeated closure, low-lid startup, wake reset, invalid angles")
    }
}
