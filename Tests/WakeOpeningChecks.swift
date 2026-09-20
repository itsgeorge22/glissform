import Foundation

@main struct WakeOpeningChecks {
    static func main() {
        func waking(angle: Double? = 8, age: Double = 0.1) -> WakeOpening {
            var wake = WakeOpening()
            wake.prepareForSleep(angle: angle, sampleAge: age)
            wake.resume(time: 100)
            return wake
        }
        for (angle, age) in [(70.0, 0.1), (8, 1.1), (Double.nan, 0.1), (8, -1)] {
            precondition(!waking(angle: angle, age: age).pending, "Only a recent near-closed lid may arm wake")
        }
        precondition(!waking(angle: nil).pending)
        var wake = waking()
        precondition(wake.pending && !wake.resume(time: 101), "Duplicate wake cannot extend the deadline")
        precondition(wake.observe(angle: 12, time: 100.01, referenceAngle: 100, desktopAvailable: true) == .waiting)
        precondition(wake.observe(angle: 13, time: 100.04, referenceAngle: 100, desktopAvailable: true) == .waiting)
        precondition(wake.observe(angle: 14, time: 100.07, referenceAngle: 100, desktopAvailable: true) == .prepare)
        precondition(wake.observe(angle: 20, time: 100.10, referenceAngle: 100, desktopAvailable: true) == .waiting,
                     "At most one preparation per wake")
        precondition(wake.canPresent(time: 100.11, referenceAngle: 100, desktopAvailable: true))
        precondition(!wake.canPresent(time: 100.36, referenceAngle: 100, desktopAvailable: true))
        precondition(!wake.canPresent(time: 100.11, referenceAngle: 100, desktopAvailable: false))
        precondition(!wake.canPresent(time: 100.11, referenceAngle: 20, desktopAvailable: true))
        precondition(wake.observe(angle: 17, time: 100.13, referenceAngle: 100, desktopAvailable: true) == .skip("reversed before reveal"))

        wake = waking()
        precondition(wake.observe(angle: 98, time: 100.01, referenceAngle: 100, desktopAvailable: true) == .skip("lid already open"))
        precondition(wake.observe(angle: 30, time: 103.01, referenceAngle: 100, desktopAvailable: true) == .skip("wake window expired"))
        precondition(wake.expired(time: 103.01))
        wake = waking()
        _ = wake.observe(angle: 12, time: 100.01, referenceAngle: 100, desktopAvailable: false)
        precondition(wake.observe(angle: 16, time: 100.04, referenceAngle: 100, desktopAvailable: false) == .waiting,
                     "Locked/unavailable desktops must not request pixels")
        precondition(wake.observe(angle: 100, time: 100.1, referenceAngle: 100, desktopAvailable: true) == .skip("lid already open"),
                     "Unlock does not replay a completed opening")
        wake = waking()
        _ = wake.observe(angle: 12, time: 100.01, referenceAngle: 100, desktopAvailable: false)
        _ = wake.observe(angle: 40, time: 100.04, referenceAngle: 100, desktopAvailable: false)
        precondition(wake.observe(angle: 30, time: 100.07, referenceAngle: 100, desktopAvailable: true) == .waiting,
                     "Delayed desktop readiness while closing cannot trigger opening")
        precondition(wake.observe(angle: 32, time: 100.10, referenceAngle: 100, desktopAvailable: true) == .prepare)
        precondition(wake.observe(angle: 34, time: 100.13, referenceAngle: 100, desktopAvailable: true) == .waiting,
                     "Pre-preparation peaks cannot look like a reversal of the new opening")
        wake = waking()
        _ = wake.observe(angle: 12, time: 100.01, referenceAngle: 100, desktopAvailable: true)
        precondition(wake.observe(angle: 40, time: 100.5, referenceAngle: 100, desktopAvailable: true) == .waiting,
                     "A sample gap is not proof of current motion")
        precondition(wake.observe(angle: 38, time: 100.53, referenceAngle: 100, desktopAvailable: true) == .waiting,
                     "Closing must not trigger opening")
        precondition(wake.observe(angle: 40, time: 100.56, referenceAngle: 100, desktopAvailable: true) == .prepare)
        precondition(wake.observe(angle: 44, time: 101, referenceAngle: 100, desktopAvailable: true) == .skip("sensor gap"))
        wake = waking()
        precondition(wake.observe(angle: .nan, time: 100.01, referenceAngle: 100, desktopAvailable: true) == .skip("invalid sensor reading"))

        var motion = ClosingMotion()
        motion.startAngle = 100
        precondition(motion.update(angle: 20, time: 0) == 0 && !motion.active)
        let folded = motion.beginOpening(angle: 20, time: 0.03)
        precondition(folded > 0 && motion.active)
        precondition(motion.update(angle: 60, time: 0.06) < folded)
        precondition(motion.update(angle: 100, time: 0.09) == 0 && !motion.active)
        motion.reset()
        precondition(motion.update(angle: 20, time: 1) == 0 && !motion.active,
                     "Ordinary reset remains unarmed below the threshold")
        print("PASS: wake eligibility, duplicate notifications, fresh opening, deadlines, lock gating, direction, sample gaps and motion arming")
    }
}
