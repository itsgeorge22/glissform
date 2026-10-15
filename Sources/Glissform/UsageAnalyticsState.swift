import Foundation

/// Consent-gated counts only. No sensor readings, screen content or gesture timestamps.
struct UsageAnalyticsState: Codable {
    enum Consent: String, Codable { case undecided, allowed, declined }
    struct Event: Codable {
        let id: UUID
        let name: String
        let day: Date
        let installationID: String
        var closeCount: Int?
    }
    struct Day: Codable {
        var closes = 0
    }
    var consent: Consent = .undecided
    var installationID: String?
    let firstSeen: Date
    var eligibleNewInstallation: Bool
    var enrolled = false
    var newInstallationEnrolled = false
    var setupCompleted = false
    var days: [String: Day] = [:]
    var pending: [Event] = []

    init(now: Date, hasPreviousInstallation: Bool) {
        firstSeen = now
        eligibleNewInstallation = !hasPreviousInstallation
    }

    static func day(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 86_400) * 86_400)
    }
    static func key(_ date: Date) -> String { String(Int(day(date).timeIntervalSince1970)) }

    mutating func choose(_ value: Consent, at now: Date) {
        guard value != consent else { return }
        consent = value
        guard value == .allowed else {
            installationID = nil
            days = [:]
            pending = []
            // Later opt-in cannot backfill the period during which sharing was off.
            eligibleNewInstallation = false
            newInstallationEnrolled = false
            return
        }
        installationID = "app_" + UUID().uuidString.lowercased()
        newInstallationEnrolled = !enrolled && eligibleNewInstallation
            && now.timeIntervalSince(firstSeen) >= 0 && now.timeIntervalSince(firstSeen) < 86_400
        if newInstallationEnrolled { enqueue("app_first_launch", day: Self.day(now)) }
        enrolled = true
        tick(at: now)
    }

    mutating func tick(at now: Date) {
        guard consent == .allowed, installationID != nil else { return }
        let today = Self.day(now)
        // Finalize a day's count once. Never replay a burst of individual gestures.
        for key in days.keys.sorted() {
            guard let seconds = TimeInterval(key), seconds < today.timeIntervalSince1970 else { continue }
            if let bucket = days[key], bucket.closes > 0 {
                enqueue("seamless_close_daily", day: Date(timeIntervalSince1970: seconds), count: bucket.closes)
            }
            days.removeValue(forKey: key)
        }
        let key = Self.key(now)
        if days[key] == nil {
            days[key] = Day()
            enqueue("app_running_day", day: today)
        }
        // Bounded offline storage; old data must not grow indefinitely.
        pending.removeAll { $0.day < today.addingTimeInterval(-30 * 86_400) }
        if pending.count > 128 { pending.removeFirst(pending.count - 128) }
    }

    mutating func recordClose(at now: Date) {
        guard consent == .allowed else { return }
        tick(at: now)
        let key = Self.key(now)
        if days[key]?.closes == 0 {
            enqueue("seamless_close_used_day", day: Self.day(now))
        }
        days[key]?.closes += 1
        if newInstallationEnrolled && !setupCompleted {
            let elapsed = now.timeIntervalSince(firstSeen)
            if elapsed >= 0 && elapsed < 7 * 86_400 {
                enqueue("app_setup_completed", day: Self.day(now))
                setupCompleted = true
            }
        }
    }

    mutating func acknowledge(_ ids: Set<UUID>) {
        pending.removeAll { ids.contains($0.id) }
    }

    private mutating func enqueue(_ name: String, day: Date, count: Int? = nil) {
        guard let installationID else { return }
        pending.append(Event(id: UUID(), name: name, day: day, installationID: installationID, closeCount: count))
    }
}
