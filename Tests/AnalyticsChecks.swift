import Foundation

@main
struct AnalyticsChecks {
    static func main() throws {
        let day = Date(timeIntervalSince1970: 1_792_022_400)
        let start = UsageAnalyticsState.day(day).addingTimeInterval(3600)
        var state = UsageAnalyticsState(now: start, hasPreviousInstallation: false)
        state.tick(at: start)
        state.recordClose(at: start)
        precondition(state.installationID == nil && state.days.isEmpty && state.pending.isEmpty, "Nothing collected before consent")
        state.choose(.allowed, at: start)
        let id = state.installationID
        precondition(state.pending.filter { $0.name == "app_first_launch" }.count == 1)
        state.tick(at: start.addingTimeInterval(3600))
        precondition(state.pending.filter { $0.name == "app_running_day" }.count == 1, "No heartbeat duplication")
        state.recordClose(at: start)
        state.recordClose(at: start.addingTimeInterval(60))
        precondition(state.pending.filter { $0.name == "seamless_close_used_day" }.count == 1)
        precondition(state.pending.filter { $0.name == "app_setup_completed" }.count == 1)
        precondition(!state.pending.contains { $0.name == "seamless_close_daily" }, "Current day remains local")
        state = try JSONDecoder().decode(UsageAnalyticsState.self, from: JSONEncoder().encode(state))
        precondition(state.installationID == id)
        state.tick(at: start.addingTimeInterval(86_400))
        let summary = state.pending.first { $0.name == "seamless_close_daily" }!
        precondition(summary.closeCount == 2 && summary.day == UsageAnalyticsState.day(start))
        let queued = state.pending.map(\.id)
        state.tick(at: start.addingTimeInterval(86_400 + 60))
        precondition(state.pending.map(\.id) == queued, "Retries reuse event UUIDs and do not duplicate summaries")
        state.acknowledge([summary.id])
        precondition(!state.pending.contains { $0.id == summary.id })
        state.choose(.declined, at: start)
        precondition(state.installationID == nil && state.pending.isEmpty && state.days.isEmpty)
        state.recordClose(at: start)
        state.tick(at: start)
        precondition(state.days.isEmpty && state.pending.isEmpty)
        state.choose(.allowed, at: start)
        precondition(state.installationID != id && !state.pending.contains { $0.name == "app_first_launch" }, "Opt-in again is not another install")

        var existing = UsageAnalyticsState(now: start, hasPreviousInstallation: true)
        existing.choose(.allowed, at: start)
        existing.recordClose(at: start)
        precondition(!existing.pending.contains { ["app_first_launch", "app_setup_completed"].contains($0.name) }, "An upgrade is not a first launch")
        var late = UsageAnalyticsState(now: start, hasPreviousInstallation: false)
        late.choose(.allowed, at: start)
        late.recordClose(at: start.addingTimeInterval(7 * 86_400))
        precondition(!late.pending.contains { $0.name == "app_setup_completed" }, "Seven-day activation window is bounded")
        late.tick(at: start.addingTimeInterval(40 * 86_400))
        precondition(late.pending.count == 1 && late.pending[0].name == "app_running_day", "Sleep creates no invented activity on missing days; offline queue expires")
        print("PASS: analytics consent, daily counts, restart, retry identity, upgrade, activation, offline expiry and withdrawal")
    }
}
