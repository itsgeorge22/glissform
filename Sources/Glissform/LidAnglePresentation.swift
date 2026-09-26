import Foundation

/// Stabilizes only the angle shown in Settings. Gesture logic uses raw sensor readings.
struct LidAnglePresentation {
    private static let oneDegreeHold = 0.25
    private(set) var angle: Double?
    private var pendingAngle: Double?
    private var pendingSince: Double?
    private var lastSampleTime: Double?

    mutating func reset() {
        angle = nil
        pendingAngle = nil
        pendingSince = nil
        lastSampleTime = nil
    }

    mutating func ingest(_ reading: Double, at time: Double) -> Double? {
        guard reading.isFinite, (0...180).contains(reading), time.isFinite else { return angle }
        defer { lastSampleTime = time }

        guard let shown = angle else {
            angle = reading
            return angle
        }
        if reading == shown {
            pendingAngle = nil
            pendingSince = nil
        } else if abs(reading - shown) >= 2 {
            angle = reading
            pendingAngle = nil
            pendingSince = nil
        } else if pendingAngle != reading || lastSampleTime.map({ time < $0 || time - $0 > 0.25 }) == true {
            pendingAngle = reading
            pendingSince = time
        } else if time - (pendingSince ?? time) >= Self.oneDegreeHold {
            angle = reading
            pendingAngle = nil
            pendingSince = nil
        }
        return angle
    }
}
