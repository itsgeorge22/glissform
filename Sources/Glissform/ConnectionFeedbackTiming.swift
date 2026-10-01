import Foundation

/// Both the display link and audio host clock use seconds since boot.
enum ConnectionFeedbackTiming {
    static let attack = 0.030
    // Keep the click's contact offset, but let the light approach that same
    // peak over more frames instead of flashing up only after reaching flat.
    static let glowAttack = 0.065
    static let decay = 0.180
    static let retreat = 0.320
    static let schedulingLead = 0.020

    struct Playback {
        let renderStart: Double
        let audiblePeak: Double
    }

    static func playback(requestedPeak: Double, now: Double, latency: Double,
                         samplePeak: Double) -> Playback {
        let outputDelay = latency.isFinite ? max(0, latency) : 0
        let peakOffset = samplePeak.isFinite ? max(0, samplePeak) : 0
        let start = max(now + schedulingLead, requestedPeak - outputDelay - peakOffset)
        return Playback(renderStart: start, audiblePeak: start + outputDelay + peakOffset)
    }
}
