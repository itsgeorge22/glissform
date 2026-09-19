import Foundation

@main struct MotionChecks {
    static func main() {
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
        print("PASS: ordinary angles, closing progression, reversal, repeated closure, low-lid startup, wake reset, invalid angles")
    }
}
