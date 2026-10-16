import Foundation

@main struct MotionChecks {
    static func main() {
        setbuf(stdout, nil)
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
        let rippleLimits: [Double: Double] = [2: 0.49, 5: 0.20, 7: 0.22, 12: 0.24,
                                             20: 0.14, 30: 0.04, 45: 0.10, 60: 0.07, 90: 0.07]
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

        // Hundredth-degree reports allow steadier, closer tracking than sparse
        // whole-degree updates. Include stationary-scale noise rather than a
        // perfectly linear sensor, and bound both delay and speed variation.
        for pollRate in [30.0, 60.0] {
            for speed in [2.0, 5.0, 20.0, 30.0] {
                var fine = MotionSmoothing()
                fine.reset(at: 0)
                var nextSample = 0
                var delay = 0.0
                var delayCount = 0
                var squaredSpeedError = 0.0
                var speedCount = 0
                var previousAngle = 0.0
                for frame in 1...360 {
                    let time = Double(frame) / 120
                    while Double(nextSample) / pollRate <= time + 0.0000001 {
                        let acquiredAt = Double(nextSample) / pollRate
                        let noise = 0.015 * sin(Double(nextSample) * 1.7)
                        let reported = ((acquiredAt * speed + noise) * 100).rounded() / 100
                        fine.ingest(target: Float(reported * .pi / 180), at: acquiredAt)
                        nextSample += 1
                    }
                    let rendered = fine.step(at: time)
                    precondition(rendered >= 0 && rendered <= fine.target + 0.000001,
                                 "Fine tracking must stay within observed lid motion")
                    let angle = Double(rendered) * 180 / .pi
                    if time > 0.5 {
                        delay += abs(angle - speed * time) / speed
                        delayCount += 1
                    }
                    if time > 1 {
                        squaredSpeedError += pow((angle - previousAngle) * 120 - speed, 2)
                        speedCount += 1
                    }
                    previousAngle = angle
                }
                let meanDelay = delay / Double(delayCount)
                let ripple = sqrt(squaredSpeedError / Double(speedCount)) / speed
                precondition(meanDelay < (speed == 2 ? 0.120 : 0.105),
                             "Fractional motion must track without excessive lag at \(speed)°/s")
                precondition(ripple < (speed == 2 ? 0.15 : speed == 5 ? 0.07 : 0.04),
                             "Faster tracking must remain visually even at \(speed)°/s")
            }
        }
        var fineStop = MotionSmoothing()
        fineStop.reset(at: 0)
        var fineAtTurn = 0.0
        var fineAfterTurn = 0.0
        for sample in 1...84 {
            let time = Double(sample) / 60
            let physical = 2 * min(time, 1)
            let noise = time > 1 ? 0.02 * sin(Double(sample) * 1.7) : 0
            fineStop.ingest(target: Float((physical + noise) * .pi / 180), at: time)
            let angle = Double(fineStop.step(at: time)) * 180 / .pi
            if sample == 60 { fineAtTurn = angle }
            if sample == 84 { fineAfterTurn = angle }
            precondition(fineStop.value <= fineStop.target + 0.000001,
                         "A stopped lid must never be extrapolated past its last reading")
        }
        precondition(fineAtTurn < 2 && abs(fineAfterTurn - 2) < 0.08,
                     "Fine tracking must settle promptly without following stationary sensor noise")
        var fineReverse = MotionSmoothing()
        fineReverse.reset(at: 0)
        var reversingAt130 = 0.0
        var reversingAt200 = 0.0
        for sample in 1...72 {
            let time = Double(sample) / 60
            let physical = time <= 1 ? 2 * time : 2 - 2 * (time - 1)
            fineReverse.ingest(target: Float(physical * .pi / 180), at: time)
            let angle = Double(fineReverse.step(at: time)) * 180 / .pi
            if sample == 68 { reversingAt130 = angle }
            if sample == 72 { reversingAt200 = angle }
        }
        precondition(reversingAt200 < reversingAt130,
                     "Slow fractional reversal must brake and change direction without a long tail")
        print("PASS: noisy fractional tracking, prompt stop and slow reversal without extrapolation")

        // The development Mac's real fast close supplied new angles about
        // every 100 ms despite 60 Hz polling. Keep motion travelling between
        // those reports without the old accelerate/settle pulse.
        let fastClose: [(Double, Double)] = [
            (0.000, 110.46), (0.100, 103.68), (0.200, 96.52),
            (0.300, 90.18), (0.400, 82.30), (0.500, 72.89),
            (0.600, 60.72), (0.700, 51.52), (0.784, 43.44),
            (0.884, 36.51), (0.983, 31.04), (1.083, 25.66),
            (1.183, 19.87), (1.283, 17.95), (1.383, 18.01)
        ]
        var sparseClose = MotionSmoothing()
        sparseClose.reset(at: 0)
        var report = 0
        var fastSpeeds: [Double] = []
        for frame in 0...90 {
            let time = Double(frame) / 60
            while report < fastClose.count && fastClose[report].0 <= time + 0.0000001 {
                sparseClose.ingest(target: Float(max(0, 105 - fastClose[report].1) * .pi / 180),
                                   at: fastClose[report].0)
                report += 1
            }
            _ = sparseClose.step(at: time)
            if time > 0.25 && time < 0.8 { fastSpeeds.append(sparseClose.velocity * 180 / .pi) }
        }
        let averageSpeed = fastSpeeds.reduce(0, +) / Double(fastSpeeds.count)
        let speedVariation = sqrt(fastSpeeds.reduce(0) { $0 + pow($1 - averageSpeed, 2) }
                                  / Double(fastSpeeds.count))
        precondition(speedVariation < 28 && averageSpeed > 80,
                     "Measured fast-close replay must advance evenly without excessive lag")

        var suddenStop = MotionSmoothing()
        suddenStop.reset(at: 0)
        var peak = 0.0
        for frame in 0...84 {
            let time = Double(frame) / 60
            if frame.isMultiple(of: 6) {
                let angle = min(100, Double(frame) / 6 * 10)
                suddenStop.ingest(target: Float(angle * .pi / 180), at: time)
            }
            peak = max(peak, Double(suddenStop.step(at: time)) * 180 / .pi)
        }
        precondition(peak < 101 && abs(Double(suddenStop.value) * 180 / .pi - 100) < 0.05,
                     "Fast sparse tracking must brake near an abrupt stop and settle")
        suddenStop.ingest(target: 0, at: 1.5)
        for frame in 91...150 { _ = suddenStop.step(at: Double(frame) / 60) }
        precondition(suddenStop.value == 0 && suddenStop.velocity == 0,
                     "Returning to the flat endpoint must not predict through zero")
        var sparse60 = MotionSmoothing()
        var sparse120 = MotionSmoothing()
        sparse60.reset(at: 0)
        sparse120.reset(at: 0)
        for frame in 0...180 {
            let time = Double(frame) / 120
            if frame.isMultiple(of: 12) {
                let angle = min(100, Double(frame / 12) * 10) * Double.pi / 180
                sparse60.ingest(target: Float(angle), at: time)
                sparse120.ingest(target: Float(angle), at: time)
            }
            let finer = sparse120.step(at: time)
            if frame.isMultiple(of: 2) {
                let coarser = sparse60.step(at: time)
                precondition(abs(finer - coarser) < 0.000001,
                             "Sparse continuation must not depend on display query frequency")
            }
        }
        print("PASS: measured 10 Hz fast close moves evenly; abrupt 100°/s stop remains bounded")

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

        var chatter = MotionSmoothing()
        chatter.reset(at: 0)
        chatter.ingest(target: 10 * degree, at: 0)
        _ = chatter.step(at: 1)
        for frame in 1...60 {
            let time = 1 + Double(frame) / 60
            chatter.ingest(target: (frame.isMultiple(of: 2) ? 10 : 9) * degree, at: time)
            precondition(abs(chatter.step(at: time) - 10 * degree) < 0.00001,
                         "Alternating one-degree chatter must not kick the desktop backwards")
        }
        for frame in 1...12 {
            let time = 2 + Double(frame) / 60
            chatter.ingest(target: 9 * degree, at: time)
            _ = chatter.step(at: time)
        }
        precondition(chatter.value < 9.2 * degree,
                     "A sustained one-degree reversal must pass the chatter gate promptly")
        precondition(chatter.step(at: 3) == 9 * degree,
                     "Chatter protection must not discard a real one-degree adjustment")

        var reversing = MotionSmoothing()
        reversing.reset(at: 0)
        for frame in 1...60 {
            let time = Double(frame) / 60
            reversing.ingest(target: Float((time * 30).rounded()) * degree, at: time)
            _ = reversing.step(at: time)
        }
        let turningPoint = reversing.value
        let incomingSpeed = reversing.velocity
        reversing.ingest(target: 25 * degree, at: 1)
        precondition(reversing.step(at: 1) == turningPoint
                     && abs(reversing.velocity - incomingSpeed) < 0.000001,
                     "A real reversal must keep position and velocity continuous")
        _ = reversing.step(at: 1.080)
        precondition(reversing.velocity < 0 && reversing.value < turningPoint,
                     "Preserved momentum must brake into a real reversal within 80 ms")
        print("PASS: one-degree chatter rejection, sustained fine adjustment and continuous reversal")

        for fold in [0.1, 0.5, 2.0, 30.0, 100.0] {
            for speed in [0.0, -2.0, -30.0, -90.0] {
                var flat = ProgrammaticReturn()
                let origin = Float(fold) * degree
                let radiansPerSecond = speed * .pi / 180
                flat.begin(from: origin, velocity: radiansPerSecond)
                precondition(flat.step(elapsed: 0) == origin && flat.velocity == radiansPerSecond,
                             "Disabling must preserve the displayed position and speed")
                var previous = origin
                for _ in 0..<66 {
                    let value = flat.step(elapsed: 0.010)
                    precondition(value >= 0 && value <= previous,
                                 "The flat return must brake without overshooting or bouncing")
                    previous = value
                }
                precondition(previous == 0 && flat.velocity == 0 && !flat.active,
                             "Even deep returns must finish before the cleanup watchdog")
            }
        }
        var gentleReturn = ProgrammaticReturn()
        gentleReturn.begin(from: degree, velocity: -2 * .pi / 180)
        precondition(gentleReturn.step(elapsed: 0.060) > degree * 0.7,
                     "A slow programmatic stop must not be forced flat in four display frames")
        var return60 = ProgrammaticReturn(), return120 = ProgrammaticReturn()
        return60.begin(from: 3 * degree, velocity: -0.3)
        return120 = return60
        for _ in 0..<12 { _ = return60.step(elapsed: 1.0 / 60) }
        for _ in 0..<24 { _ = return120.step(elapsed: 1.0 / 120) }
        precondition(abs(return60.step(elapsed: 0) - return120.step(elapsed: 0)) < 0.000001,
                     "Return timing must not depend on display refresh rate")
        print("PASS: velocity-continuous programmatic stops and bounded cleanup")

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
        let radians = Float.pi / 180
        var previousImageAngle: Float = -1
        var previousTopWidth: Float = 1
        for degree in 0...130 {
            let physicalAngle = Float(degree) * radians
            let imageAngle = ScreenProjection.imageRadians(for: physicalAngle)
            let topWidth = ScreenProjection.topWidth(for: physicalAngle)
            precondition(imageAngle > previousImageAngle,
                         "Image projection must keep moving through full closure")
            if degree > 0 {
                precondition(topWidth < previousTopWidth,
                             "Upper edge and image content must move together through closure")
            }
            if degree >= 45 {
                precondition(previousTopWidth - topWidth > 0.0035,
                             "Late geometry must keep changing visibly per lid degree")
            }
            let depth = sin(imageAngle)
            let projectedTop = (4 * cos(imageAngle) - 1.1 * depth) / (4 - depth)
            precondition(abs(topWidth - projectedTop) < 0.027,
                         "Top edge and image source height must remain visually aligned")
            previousImageAngle = imageAngle
            previousTopWidth = topWidth
        }
        let earlyAngle = ScreenProjection.imageRadians(for: 25 * radians)
        precondition(earlyAngle > 23 * radians && earlyAngle < 25 * radians,
                     "The first quarter of the fold must retain a prompt projection response")
        let finalAngle = ScreenProjection.imageRadians(for: 130 * radians)
        let finalDepth = sin(finalAngle)
        let sampledHeight = (4 * cos(finalAngle) - 1.1 * finalDepth) / (4 - finalDepth)
        precondition(sampledHeight > 0.43 && sampledHeight < 0.45,
                     "Deep closure must sample enough image height to avoid excessive stretch")
        precondition(abs(ScreenProjection.topWidth(for: 130 * radians) - 0.42) < 0.00001,
                     "Upper-edge tightening must remain bounded at the deepest fold")
        for reference in [20.0, 85, 100, 105, 130] {
            var previousWidth = ScreenProjection.topWidth(for: 0)
            precondition(abs(previousWidth - 1) < 0.00001)
            for lid in stride(from: reference - 1, through: 4, by: -1) {
                let fold = ScreenProjection.foldRadians(lidAngle: lid, referenceAngle: reference)
                let width = ScreenProjection.topWidth(for: fold)
                precondition(width < previousWidth,
                             "Every supported start angle must retain visible geometry motion")
                previousWidth = width
            }
            precondition(previousWidth >= ScreenProjection.topWidth(for: 130 * radians),
                         "A shorter fold must not narrow farther than the maximum fold")
        }
        let widthAt60 = ScreenProjection.topWidth(for: ScreenProjection.foldRadians(lidAngle: 60, referenceAngle: 105))
        let widthAt4 = ScreenProjection.topWidth(for: ScreenProjection.foldRadians(lidAngle: 4, referenceAngle: 105))
        precondition(widthAt60 - widthAt4 > 0.245,
                     "Upper edge must continue tightening visibly below a 60° lid angle")
        precondition(widthAt4 > 0.545 && widthAt4 < 0.555,
                     "Default-length closure must retain its intended final width")
        print("PASS: one continuous geometry response, bounded vertical stretch and late top narrowing")
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
                precondition(abs(value - 0.5) < 0.00001,
                             "Pause restoration must use balanced motion instead of an early surge")
            }
            previousPauseValue = value
        }
        precondition(previousPauseValue == 0 && pauseReturn.velocity == 0 && !pauseReturn.active,
                     "Pause restoration must finish exactly flat and at rest")
        print("PASS: eased pause restoration, monotonic return and exact flat finish")

        for fold in [1.0, 15.0, 60.0, 120.0] {
            let origin = Float(fold) * degree
            let duration = HandoffTransition.pauseRestorationDuration(for: origin)
            var restored = HandoffTransition()
            restored.begin(from: origin, duration: duration, holdFirstFrame: false, curve: .pauseRestoration)
            var peakSpeed = 0.0
            for _ in 0..<650 {
                _ = restored.step(toward: 0, elapsed: 0.001)
                peakSpeed = max(peakSpeed, abs(restored.velocity))
            }
            let previousDuration = min(0.480, 0.260 + Double(origin) * 0.16)
            precondition(peakSpeed < 1.875 * Double(origin) / previousDuration,
                         "Pause restoration must reduce peak speed at shallow and deep folds")
            precondition(!restored.active && restored.velocity == 0 && duration + 0.050 < 0.8,
                         "Pause return and fade must finish before the watchdog")
        }
        print("PASS: lower pause-return peak speed across shallow and deep folds")

        for speed in [10.0, 40.0, 80.0] {
            var continuation = OpeningContinuation()
            let initialVelocity = -0.5 * speed * Double(degree)
            continuation.begin(from: 10 * degree, velocity: initialVelocity,
                               observedSpeed: speed)
            precondition(abs(continuation.velocity - initialVelocity) < 0.000001,
                         "Assisted opening must keep the exact velocity visible at takeover")
            var previousFold = 10 * degree
            var reachedMeasuredSpeed = false
            for _ in 0..<900 where continuation.active {
                let fold = continuation.step(elapsed: 1.0 / 120)
                let visibleSpeed = -continuation.velocity
                precondition(fold >= 0 && fold <= previousFold,
                             "Assisted opening must stay monotonic through flat")
                precondition(visibleSpeed >= 0 && visibleSpeed <= speed * Double(degree) + 0.000001,
                             "Assisted opening must not exceed the measured hand speed")
                if abs(visibleSpeed - speed * Double(degree)) < 0.000001 { reachedMeasuredSpeed = true }
                previousFold = fold
            }
            precondition(reachedMeasuredSpeed && !continuation.active
                         && previousFold == 0 && continuation.velocity == 0,
                         "Assisted opening must reach hand speed, then end flat and at rest")
        }
        var sixtyHertz = OpeningContinuation(), oneTwentyHertz = OpeningContinuation()
        sixtyHertz.begin(from: 10 * degree, velocity: -40 * Double(degree), observedSpeed: 80)
        oneTwentyHertz.begin(from: 10 * degree, velocity: -40 * Double(degree), observedSpeed: 80)
        for _ in 0..<6 { _ = sixtyHertz.step(elapsed: 1.0 / 60) }
        for _ in 0..<12 { _ = oneTwentyHertz.step(elapsed: 1.0 / 120) }
        precondition(abs(sixtyHertz.step(elapsed: 0) - oneTwentyHertz.step(elapsed: 0)) < 0.000001,
                     "The continuation must have the same position at 60 and 120 Hz")
        var fromRest = OpeningContinuation()
        fromRest.begin(from: 84 * degree, velocity: 0, observedSpeed: 100)
        precondition(fromRest.velocity == 0, "A cached image must not jump to the sensor speed")
        _ = fromRest.step(elapsed: 1.0 / 120)
        precondition(-fromRest.velocity < 5 * Double(degree),
                     "A stationary cached image must ease into the measured pace")
        for _ in 0..<239 where fromRest.active {
            _ = fromRest.step(elapsed: 1.0 / 120)
        }
        precondition(!fromRest.active && fromRest.velocity == 0,
                     "A cached image with no visible velocity must still finish promptly")
        // Dense samples catch a sudden brake at the cruise/landing join even
        // when position remains monotonic at display-frame intervals.
        for (foldDegrees, entrySpeed, measuredSpeed) in [(5.0, 40.0, 40.0), (0.5, 20.0, 80.0)] {
            var continuation = OpeningContinuation()
            continuation.begin(from: Float(foldDegrees) * degree,
                               velocity: -entrySpeed * Double(degree), observedSpeed: measuredSpeed)
            let delta = foldDegrees < 1 ? 0.0000005 : 0.00005
            var previousVelocity = continuation.velocity
            var previousAcceleration = 0.0
            var previousFold = Float(foldDegrees) * degree
            var time = 0.0
            var previousProgress: Float = 0
            while continuation.active && time < 1 {
                let fold = continuation.step(elapsed: delta)
                let acceleration = (continuation.velocity - previousVelocity) / delta
                precondition(abs(acceleration - previousAcceleration) < 2,
                             "Assisted speed changes must join without a sudden acceleration step")
                precondition(fold.isFinite && fold >= 0 && fold <= previousFold,
                             "A shallow fast assist must reach flat without overshooting")
                precondition(continuation.completionFraction >= previousProgress
                             && continuation.completionFraction <= 1,
                             "Connection timing must advance monotonically at every opening speed")
                previousVelocity = continuation.velocity
                previousAcceleration = acceleration
                previousFold = fold
                previousProgress = continuation.completionFraction
                time += delta
            }
            precondition(!continuation.active && previousFold == 0
                         && continuation.velocity == 0 && continuation.completionFraction == 1,
                         "The refined landing must finish flat without a lingering motion tail")
            if foldDegrees == 5 {
                precondition(abs(time - 0.14375) < 0.0001,
                             "Smoothing the landing must preserve the measured opening duration")
            }
        }
        print("PASS: assisted opening blends into measured hand speed, finishes promptly, and is frame-rate independent")

        // The finish must carry a faster visible image even when the estimate
        // trails an accelerating hand, including movement above the old cap.
        for (entry, estimate, acceleration) in [(49.0, 45.0, 100.0), (180.0, 120.0, 0.0),
                                                 (40.0, 40.0, 200.0), (20.0, 80.0, 50.0)] {
            var continuation = OpeningContinuation()
            continuation.begin(from: 10 * degree, velocity: -entry * Double(degree),
                               acceleration: -acceleration * Double(degree), observedSpeed: estimate)
            let entryVelocity = continuation.velocity
            _ = continuation.step(elapsed: 0.000001)
            let entryAcceleration = -(continuation.velocity - entryVelocity) / 0.000001 / Double(degree)
            precondition(abs(entryAcceleration - acceleration) < 0.02,
                         "The handoff must carry bounded opening acceleration instead of resetting it")
            var previousFold = 10 * degree
            var elapsed = 0.000001
            while continuation.active && elapsed < 3 {
                let fold = continuation.step(elapsed: 1.0 / 120)
                elapsed += 1.0 / 120
                precondition(fold.isFinite && fold >= 0 && fold <= previousFold,
                             "Momentum must finish monotonically without overshooting")
                if fold > 1.5 * degree {
                    precondition(-continuation.velocity / Double(degree) >= entry - 0.0001,
                                 "An older estimate must not brake the image before the landing")
                }
                previousFold = fold
            }
            precondition(!continuation.active && previousFold == 0 && continuation.velocity == 0,
                         "Carried momentum must finish flat promptly")
        }
        // Replay the actual sensor -> smoothing -> takeover path with fractional
        // and whole-degree input, varying acquisition/display phase and cadence.
        for quantized in [false, true] {
            for cadence in [1.0 / 60, 1.0 / 30, 0.100] {
                for phase in [0.0, 0.004, 0.012] {
                    var tracking = MotionSmoothing()
                    var assist = OpeningAssist()
                    var continuation = OpeningContinuation()
                    tracking.reset(to: 20 * degree, at: 0)
                    var sample = 0
                    var pendingSpeed: Double?
                    var started = false
                    var previousVelocity = 0.0
                    var previousFold = 20 * degree
                    var entrySpeed = 0.0
                    for frame in 0...180 {
                        let time = Double(frame) / 60
                        while phase + Double(sample) * cadence <= time {
                            let acquired = phase + Double(sample) * cadence
                            let raw = min(100, 80 + 10 * acquired + 50 * acquired * acquired)
                            let angle = quantized ? raw.rounded(.down) : raw
                            tracking.ingest(target: Float((100 - angle) * .pi / 180), at: acquired)
                            if !started && pendingSpeed == nil {
                                pendingSpeed = assist.observe(angle: angle, time: acquired,
                                                              referenceAngle: 100, active: true)
                            }
                            sample += 1
                        }
                        let manualFold = tracking.step(at: time)
                        if let speed = pendingSpeed {
                            entrySpeed = -tracking.velocity / Double(degree)
                            continuation.begin(from: manualFold, velocity: tracking.velocity,
                                               acceleration: (tracking.velocity - previousVelocity) * 60,
                                               observedSpeed: speed)
                            precondition(continuation.step(elapsed: 0) == manualFold
                                         && continuation.velocity == tracking.velocity,
                                         "Takeover must consume the newest reading and keep the entire next lid frame")
                            pendingSpeed = nil
                            started = true
                            previousFold = manualFold
                        } else if started {
                            let fold = continuation.step(elapsed: 1.0 / 60)
                            precondition(fold.isFinite && fold >= 0 && fold <= previousFold,
                                         "An accelerated replay must remain monotonic")
                            if fold > min(previousFold, 1.5 * degree) {
                                precondition(-continuation.velocity / Double(degree) >= 0.95 * entrySpeed,
                                             "Takeover must not fall back to a much slower historical pace")
                            }
                            previousFold = fold
                            if !continuation.active { break }
                        }
                        previousVelocity = tracking.velocity
                    }
                    precondition(started && !continuation.active && previousFold == 0,
                                 "Every fractional/quantized accelerating replay must complete")
                }
            }
        }
        print("PASS: accelerated tracking handoff keeps the newest frame and bounded momentum without historical-speed braking")

        // Pause-to-resume uses a monotonic sample clock, not time since capture.
        func pausingMotion(duration: Double? = nil, enabled: Bool = true) -> ClosingMotion {
            var state = ClosingMotion()
            state.startAngle = 95
            state.resumeAfterPause = enabled
            if let duration { state.pauseDuration = duration }
            _ = state.update(angle: 100, time: -0.05)
            return state
        }
        var defaultPause = pausingMotion()
        precondition(defaultPause.pauseDuration == 1, "The app's pause wait must default to one second")
        for frame in 0...19 { _ = defaultPause.update(angle: 80, time: Double(frame) / 20) }
        precondition(defaultPause.active && !defaultPause.desktopResumed,
                     "The default pause must not expire before one second")
        precondition(defaultPause.update(angle: 80, time: 1) == 0 && defaultPause.desktopResumed,
                     "The default pause must expire at one second")
        for duration in [0.5, 1.0, 2.0, 10.0] {
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
        precondition(ClosingMotion.validStillDuration(.nan) == 1
                     && ClosingMotion.validStillDuration(0.1) == 0.5
                     && ClosingMotion.validStillDuration(20) == 10,
                     "Saved wait times must stay within the supported range")
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

        for zone in 1...10 {
            var deadZone = ClosingMotion()
            deadZone.startAngle = 95
            deadZone.automaticDeadZone = Double(zone)
            // The saved dead zone must affect neither manual mode nor fallback.
            _ = deadZone.update(angle: 110, time: 0)
            precondition(deadZone.effectiveStartAngle == 95)
            deadZone.automaticStartAngle = true
            precondition(deadZone.effectiveStartAngle == 95)
            for sample in 0...20 { _ = deadZone.update(angle: 110, time: Double(sample) / 20) }
            let boundary = 110 - Double(zone)
            precondition(deadZone.learnedStartAngle == 110 && deadZone.effectiveStartAngle == boundary)
            // Slow travel, including long stops within a large dead zone, must
            // not move the resting reference downward and swallow the gesture.
            for sample in 1...Int(Double(zone) * 100) + 1 {
                let angle = max(boundary, 110 - Double(sample) / 100)
                precondition(deadZone.update(angle: angle, time: 1 + Double(sample) / 20) == 0)
                precondition(deadZone.learnedStartAngle == 110)
            }
            let time = 2 + Double(zone) * 5
            precondition(deadZone.update(angle: boundary, time: time) == 0)
            let first = deadZone.update(angle: boundary - 0.01, time: time + 0.02)
            precondition(first > 0 && first < 0.000001 && deadZone.activationAngle == boundary,
                         "Every dead zone must enter continuously from a flat reference")
            let closing = deadZone.update(angle: boundary - 15, time: time + 0.04)
            precondition(deadZone.update(angle: boundary - 2, time: time + 0.06) < closing)
            precondition(deadZone.activationAngle == boundary, "Reversal must retain the same reference")
            deadZone.reset()
            precondition(deadZone.beginOpening(angle: 30, time: time + 0.1) > 0
                         && deadZone.activationAngle == boundary, "Cached opening must not subtract the dead zone twice")
            deadZone.automaticStartAngle = false
            precondition(deadZone.effectiveStartAngle == 95, "Turning automatic detection off restores manual mode")
        }
        precondition(ClosingMotion.validAutomaticDeadZone(.nan) == 1
                     && ClosingMotion.validAutomaticDeadZone(-1) == 1
                     && ClosingMotion.validAutomaticDeadZone(0) == 1
                     && ClosingMotion.validAutomaticDeadZone(20) == 10
                     && ClosingMotion.validAutomaticDeadZone(4.6) == 5)
        // At the default, the exact progress and reference equal the old 109°
        // trigger throughout a gesture; the renderer receives identical inputs.
        var defaultZone = ClosingMotion()
        defaultZone.startAngle = 95
        defaultZone.automaticStartAngle = true
        for sample in 0...20 { _ = defaultZone.update(angle: 110, time: Double(sample) / 20) }
        var oldReference = ClosingMotion()
        oldReference.startAngle = 109
        _ = oldReference.update(angle: 110, time: 1)
        for (index, angle) in [109.0, 108.9, 100, 80, 20, 4, 25, 80, 95, 85, 105, 109, 110].enumerated() {
            let time = 1.1 + Double(index) / 20
            precondition(defaultZone.update(angle: angle, time: time) == oldReference.update(angle: angle, time: time))
            precondition(defaultZone.activationAngle == oldReference.activationAngle
                         && defaultZone.active == oldReference.active)
        }
        print("PASS: automatic-only dead zones 1–10°, slow travel, flat entry, reversal, wake reference and exact 1° default motion")

        var automatic = ClosingMotion()
        automatic.startAngle = 95
        automatic.automaticStartAngle = true
        for frame in 0...19 {
            _ = automatic.update(angle: frame.isMultiple(of: 2) ? 110 : 111,
                                 time: Double(frame) / 20)
        }
        precondition(automatic.learnedStartAngle == nil, "A short or jittering rest must retain the manual fallback")
        _ = automatic.update(angle: 110, time: 1)
        precondition(automatic.learnedStartAngle == 110,
                     "Automatic selection must learn after one second of fresh readings")
        for frame in 21...62 { _ = automatic.update(angle: 110, time: Double(frame) / 20) }
        precondition(automatic.learnedStartAngle == 110 && automatic.effectiveStartAngle == 109,
                     "A one-second open-lid rest must start one degree below the held angle")
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
        precondition(automatic.learnedStartAngle == 110 && automatic.effectiveStartAngle == 109,
                     "A lifecycle reset must preserve the learned reference")
        precondition(automatic.beginOpening(angle: 30, time: 3.35) > 0 && automatic.activationAngle == 109,
                     "Wake opening must use the closing reference")
        automatic.automaticStartAngle = false
        precondition(automatic.learnedStartAngle == nil && automatic.effectiveStartAngle == 120,
                     "Turning automatic selection off must restore the manual angle")

        var customDetection = ClosingMotion()
        customDetection.startAngle = 95
        customDetection.automaticStartAngle = true
        customDetection.automaticAngleDuration = 2
        for frame in 0...30 { _ = customDetection.update(angle: 110, time: Double(frame) / 20) }
        precondition(customDetection.learnedStartAngle == nil,
                     "Automatic detection must wait for its selected duration")
        customDetection.automaticAngleDuration = 0.5
        for frame in 31...39 { _ = customDetection.update(angle: 110, time: Double(frame) / 20) }
        precondition(customDetection.learnedStartAngle == nil,
                     "Changing the detection time must restart its pending wait")
        _ = customDetection.update(angle: 110, time: 2.1)
        precondition(customDetection.learnedStartAngle == 110 && customDetection.pauseDuration == 1,
                     "The new detection time must apply independently from the resume time")

        var lowerThreshold = ClosingMotion()
        lowerThreshold.startAngle = 100
        lowerThreshold.automaticDetectionThreshold = 80
        lowerThreshold.automaticStartAngle = true
        for frame in 0...19 { _ = lowerThreshold.update(angle: 90, time: Double(frame) / 20) }
        precondition(lowerThreshold.effectiveStartAngle == 100,
                     "Begin at must remain the fallback before detection completes")
        _ = lowerThreshold.update(angle: 90, time: 1)
        precondition(lowerThreshold.learnedStartAngle == 90 && lowerThreshold.effectiveStartAngle == 89,
                     "A held lid above the threshold must learn even below Begin at")
        lowerThreshold.automaticDetectionThreshold = 100
        precondition(lowerThreshold.learnedStartAngle == nil && lowerThreshold.effectiveStartAngle == 100,
                     "Changing the threshold must restore the manual fallback")
        for frame in 21...45 { _ = lowerThreshold.update(angle: 90, time: Double(frame) / 20) }
        precondition(lowerThreshold.learnedStartAngle == nil,
                     "A lid below the new threshold must not relearn")
        lowerThreshold.automaticDetectionThreshold = 0
        for frame in 46...66 { _ = lowerThreshold.update(angle: 90, time: Double(frame) / 20) }
        precondition(lowerThreshold.learnedStartAngle == 90,
                     "Setting Detect above to zero must allow learning below the previous threshold")

        var defaultThreshold = ClosingMotion()
        defaultThreshold.startAngle = 90
        defaultThreshold.automaticStartAngle = true
        for frame in 0...25 { _ = defaultThreshold.update(angle: 45, time: Double(frame) / 20) }
        precondition(defaultThreshold.learnedStartAngle == nil,
                     "The default must not learn at or below 45 degrees")
        for frame in 26...51 { _ = defaultThreshold.update(angle: 46, time: Double(frame) / 20) }
        precondition(defaultThreshold.learnedStartAngle == 46,
                     "The default must allow learning strictly above 45 degrees")
        precondition(ClosingMotion.validDetectionThreshold(20) == 20,
                     "An existing saved 20-degree preference must remain valid")

        var higherThreshold = ClosingMotion()
        higherThreshold.startAngle = 100
        higherThreshold.automaticDetectionThreshold = 120
        higherThreshold.automaticStartAngle = true
        for frame in 0...25 { _ = higherThreshold.update(angle: 110, time: Double(frame) / 20) }
        precondition(higherThreshold.effectiveStartAngle == 100,
                     "Begin at must control the band below a higher detection threshold")
        for frame in 26...47 { _ = higherThreshold.update(angle: 125, time: Double(frame) / 20) }
        precondition(higherThreshold.learnedStartAngle == 125,
                     "Holding above a higher threshold must learn the new angle")
        precondition(ClosingMotion.validDetectionThreshold(.nan) == 45
                     && ClosingMotion.validDetectionThreshold(0) == 0
                     && ClosingMotion.validDetectionThreshold(5) == 20
                     && ClosingMotion.validDetectionThreshold(150) == 130,
                     "Saved detection thresholds must accept zero or stay within the supported range")
        var manualDuringThresholdEdit = ClosingMotion()
        manualDuringThresholdEdit.startAngle = 100
        _ = manualDuringThresholdEdit.update(angle: 110, time: 0)
        _ = manualDuringThresholdEdit.update(angle: 90, time: 0.05)
        precondition(manualDuringThresholdEdit.active, "The manual gesture must be active before editing")
        manualDuringThresholdEdit.automaticDetectionThreshold = 80
        precondition(manualDuringThresholdEdit.active && manualDuringThresholdEdit.effectiveStartAngle == 100,
                     "Editing the inactive automatic threshold must preserve a manual gesture")

        var belowThresholdPause = ClosingMotion()
        belowThresholdPause.startAngle = 100
        belowThresholdPause.automaticDetectionThreshold = 80
        belowThresholdPause.automaticStartAngle = true
        belowThresholdPause.resumeAfterPause = true
        _ = belowThresholdPause.update(angle: 110, time: 0)
        _ = belowThresholdPause.update(angle: 80, time: 0.05)
        for frame in 2...21 { _ = belowThresholdPause.update(angle: 80, time: Double(frame) / 20) }
        precondition(belowThresholdPause.desktopResumed && belowThresholdPause.learnedStartAngle == nil
                     && belowThresholdPause.effectiveStartAngle == 100,
                     "A pause below Detect above may restore the desktop but must not learn an angle")
        precondition(belowThresholdPause.update(angle: 79, time: 1.1) == 0
                     && belowThresholdPause.desktopResumed,
                     "A below-threshold pause must not rearm by closing past an unlearned angle")

        var learnedThenPausedBelow = ClosingMotion()
        learnedThenPausedBelow.startAngle = 100
        learnedThenPausedBelow.automaticDetectionThreshold = 80
        learnedThenPausedBelow.automaticStartAngle = true
        learnedThenPausedBelow.resumeAfterPause = true
        for frame in 0...20 { _ = learnedThenPausedBelow.update(angle: 110, time: Double(frame) / 20) }
        precondition(learnedThenPausedBelow.learnedStartAngle == 110,
                     "This pause case must start from a valid learned angle")
        for frame in 21...41 { _ = learnedThenPausedBelow.update(angle: 70, time: Double(frame) / 20) }
        _ = learnedThenPausedBelow.update(angle: 70, time: 2.1)
        precondition(learnedThenPausedBelow.desktopResumed && learnedThenPausedBelow.learnedStartAngle == nil
                     && learnedThenPausedBelow.effectiveStartAngle == 100,
                     "A pause below Detect above must restore Begin at instead of retaining a learned angle")

        var disabledThresholdPause = ClosingMotion()
        disabledThresholdPause.startAngle = 100
        disabledThresholdPause.automaticDetectionThreshold = 0
        disabledThresholdPause.automaticStartAngle = true
        disabledThresholdPause.resumeAfterPause = true
        for frame in 0...20 { _ = disabledThresholdPause.update(angle: 110, time: Double(frame) / 20) }
        for frame in 21...41 { _ = disabledThresholdPause.update(angle: 70, time: Double(frame) / 20) }
        _ = disabledThresholdPause.update(angle: 70, time: 2.1)
        precondition(disabledThresholdPause.desktopResumed && disabledThresholdPause.learnedStartAngle == 70,
                     "A zero threshold must let pause restoration learn within the supported angle range")

        var lowRest = ClosingMotion()
        lowRest.startAngle = 95
        lowRest.automaticStartAngle = true
        for frame in 0...40 { _ = lowRest.update(angle: 80, time: Double(frame) / 20) }
        precondition(lowRest.learnedStartAngle == 80 && !lowRest.active,
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
        precondition(gaps.learnedStartAngle == 110, "Fresh samples can learn after an interruption")

        var jitter = ClosingMotion()
        jitter.startAngle = 95
        jitter.automaticStartAngle = true
        for frame in 0...40 {
            _ = jitter.update(angle: frame.isMultiple(of: 2) ? 110 : 111,
                              time: Double(frame) / 20)
        }
        precondition(jitter.learnedStartAngle == 110,
                     "One-degree sensor chatter must not prevent learning")
        for frame in 41...90 {
            _ = jitter.update(angle: frame.isMultiple(of: 2) ? 110 : 111,
                              time: Double(frame) / 20)
        }
        precondition(jitter.learnedStartAngle == 110,
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
        precondition(restored.desktopResumed && restored.learnedStartAngle == 80
                     && restored.activationAngle == 109,
                     "An active pause restoration must adopt its new resting angle")
        for frame in 83...125 { _ = restored.update(angle: 80, time: Double(frame) / 20) }
        precondition(!restored.active && restored.desktopResumed && restored.effectiveStartAngle == 79,
                     "A learned pause angle must not restart the effect while still")
        precondition(restored.update(angle: 79, time: 6.27) == 0 && restored.desktopResumed,
                     "The learned starting angle must not recapture the still desktop")
        precondition(restored.update(angle: 78, time: 6.3) > 0 && restored.activationAngle == 79
                     && !restored.desktopResumed,
                     "Closing past the learned angle must restart without opening farther first")
        _ = restored.update(angle: 79, time: 6.35)
        precondition(!restored.active, "Reopening to the learned angle must finish the new gesture")
        var directlyReclosed = ClosingMotion()
        directlyReclosed.startAngle = 95
        directlyReclosed.automaticStartAngle = true
        directlyReclosed.resumeAfterPause = true
        for frame in 0...40 { _ = directlyReclosed.update(angle: 110, time: Double(frame) / 20) }
        _ = directlyReclosed.update(angle: 80, time: 2.05)
        for frame in 42...82 { _ = directlyReclosed.update(angle: 80, time: Double(frame) / 20) }
        precondition(directlyReclosed.update(angle: 78, time: 4.15) > 0,
                     "The first reading after restoration may already be below the learned angle")
        var noRestore = ClosingMotion()
        noRestore.startAngle = 95
        noRestore.automaticStartAngle = true
        for frame in 0...40 { _ = noRestore.update(angle: 110, time: Double(frame) / 20) }
        for frame in 41...95 { _ = noRestore.update(angle: 80, time: Double(frame) / 20) }
        precondition(noRestore.active && noRestore.learnedStartAngle == 110,
                     "Automatic selection must respect the separate pause-restoration toggle")
        noRestore.cancelUntilOpened(above: 109)
        for frame in 96...140 { _ = noRestore.update(angle: 80, time: Double(frame) / 20) }
        precondition(!noRestore.active && noRestore.learnedStartAngle == 110,
                     "Escape must not learn a lower angle or rearm while the lid stays closed")
        _ = noRestore.update(angle: 110, time: 7.05)
        precondition(noRestore.update(angle: 80, time: 7.1) > 0,
                     "Reopening above the escaped angle must permit a new gesture")
        print("PASS: automatic rest learning, manual fallback, gesture lock, wake reference, sample gaps and pause latch")

        var assist = OpeningAssist()
        precondition(assist.observe(angle: 70, time: 0, referenceAngle: 90, active: true) == nil)
        precondition(assist.observe(angle: 72, time: 0.1, referenceAngle: 90, active: true) == nil)
        precondition(assist.observe(angle: 78, time: 0.2, referenceAngle: 90, active: true) == nil)
        precondition(assist.observe(angle: 80, time: 0.3, referenceAngle: 90, active: true) == nil)
        precondition(assist.observe(angle: 84, time: 0.4, referenceAngle: 90, active: true) == nil,
                     "Six degrees remaining must still follow the physical lid")
        let openingSpeed = assist.observe(angle: 85, time: 0.5, referenceAngle: 90, active: true)
        precondition(openingSpeed != nil && abs(openingSpeed! - 10) < 0.01,
                     "The final five degrees must use the latest available pace, not older faster movement")
        assist.reset()
        for (angle, time) in [(85.0, 1.0), (86.0, 1.1), (85.0, 1.2), (86.0, 1.3)] {
            precondition(assist.observe(angle: angle, time: time, referenceAngle: 90, active: true) == nil,
                         "One-degree chatter must not trigger assisted opening")
        }
        precondition(assist.observe(angle: 87, time: 2.6, referenceAngle: 90, active: true) == nil,
                     "A stale sensor gap must discard opening speed")

        var fastAssist = OpeningAssist()
        var fastSpeed: Double?
        for (angle, time) in [(80.0, 0.0), (86.0, 1.0 / 30), (92.0, 2.0 / 30), (98.0, 0.1)] {
            fastSpeed = fastAssist.observe(angle: angle, time: time, referenceAngle: 100, active: true)
        }
        precondition(fastSpeed != nil && abs(fastSpeed! - 180) < 0.01,
                     "A real fast opening must not be forced down to the old 120-degree speed cap")
        var acceleratingAssist = OpeningAssist()
        var acceleratedSpeed: Double?
        for frame in 0...15 {
            let time = Double(frame) / 30
            acceleratedSpeed = acceleratingAssist.observe(angle: 80 + 10 * time + 50 * time * time,
                                                          time: time, referenceAngle: 100, active: true)
        }
        precondition(acceleratedSpeed != nil && acceleratedSpeed! > 55,
                     "The pace estimate must follow recent acceleration instead of a quarter-second average")

        var assistedManual = ClosingMotion()
        assistedManual.startAngle = 90
        _ = assistedManual.update(angle: 100, time: 0)
        _ = assistedManual.update(angle: 70, time: 0.1)
        assistedManual.completeAssistedOpening(at: 86)
        precondition(!assistedManual.active && assistedManual.desktopResumed,
                     "An early finish must restore the live desktop")
        for angle in [86.0, 85, 87, 90] {
            precondition(assistedManual.update(angle: angle, time: 0.2) == 0 && !assistedManual.active,
                         "A stationary or reclosed lid must not recapture below the manual start angle")
        }
        _ = assistedManual.update(angle: 91, time: 0.3)
        precondition(assistedManual.update(angle: 80, time: 0.4) > 0,
                     "Opening above the manual start must rearm the next gesture")
        var assistedAutomatic = ClosingMotion()
        assistedAutomatic.startAngle = 90
        assistedAutomatic.automaticStartAngle = true
        _ = assistedAutomatic.update(angle: 100, time: 0)
        _ = assistedAutomatic.update(angle: 70, time: 0.1)
        assistedAutomatic.completeAssistedOpening(at: 86)
        precondition(assistedAutomatic.learnedStartAngle == 86 && assistedAutomatic.desktopResumed,
                     "Automatic mode may learn the usable angle after an early finish")
        precondition(assistedAutomatic.update(angle: 86, time: 0.2) == 0)
        precondition(assistedAutomatic.update(angle: 84, time: 0.3) > 0,
                     "Closing below the learned angle must rearm automatically")
        print("PASS: speed-matched opening assist, chatter and stale-sample rejection, safe rearming")
        print("PASS: ordinary angles, closing progression, reversal, repeated closure, low-lid startup, wake reset, invalid angles")
    }
}
