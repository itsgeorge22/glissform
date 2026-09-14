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
        let degree = Float(0.867 * Double.pi / 180)
        for step in 1...8 {
            let target = Float(step) * degree
            let before = slow.value
            let first = slow.step(toward: target, elapsed: 1.0 / 60)
            precondition(first - before < degree * 0.25, "No abrupt jump on the degree boundary")
            var previous = first
            for frame in 1..<12 {
                let next = slow.step(toward: target, elapsed: 1.0 / 60)
                precondition(next >= previous && next <= target, "Slow motion must not overshoot")
                if frame == 11 {
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
        var handoff = HandoffTransition()
        handoff.begin(from: 0)
        precondition(handoff.step(toward: 1, elapsed: 0) == 0, "Entrance starts at the unchanged image")
        precondition(handoff.step(toward: 1, elapsed: 0.010) < 0.002, "Entrance starts gently")
        let middle = handoff.step(toward: 1, elapsed: 0.080)
        precondition(abs(middle - 0.5) < 0.001)
        handoff.begin(from: middle)
        precondition(handoff.step(toward: 0, elapsed: 0) == middle, "Interrupted entrance returns from its displayed angle")
        precondition(handoff.step(toward: 0, elapsed: 0.180) == 0 && !handoff.active,
                     "Exit reaches an exact flat image before releasing the snapshot")
        handoff.begin(from: 0.2)
        precondition(handoff.step(toward: 0.7, elapsed: 0) == 0.2, "Reclosing during exit must not jump")
        handoff.begin(from: 0)
        precondition(handoff.step(toward: 1, elapsed: 0.5) == 0,
                     "Even a late first display frame must start at exactly zero effect")
        precondition(handoff.step(toward: 1, elapsed: 0.010) < 0.002)
        print("PASS: exact zero first frame, gentle entry and exit, interrupted entrance, reclose continuity")
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
