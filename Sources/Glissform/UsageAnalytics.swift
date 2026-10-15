import Foundation

/// Small explicit PostHog capture client: no SDK autocapture or screen access.
@MainActor
final class UsageAnalytics {
    static let storageKey = "usageAnalytics.v1"
    // Public write-only project token, not an account credential.
    private let projectToken = "phc_yjUSMgbWh2MRH98S38CiCYgiNE6GCYBtHRtER7usvGLu"
    private let defaults: UserDefaults
    private let development: Bool
    private let networkEnabled: Bool
    private let sessionConfiguration: URLSessionConfiguration?
    private(set) var state: UsageAnalyticsState
    private var timer: Timer?
    private var session: URLSession?
    private var request: URLSessionDataTask?
    private var generation = 0
    private var lastAttempt = Date.distantPast

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main,
         sessionConfiguration: URLSessionConfiguration? = nil) {
        self.defaults = defaults
        self.sessionConfiguration = sessionConfiguration
        development = bundle.object(forInfoDictionaryKey: "GlissformDeveloperTools") as? Bool != false
        networkEnabled = !development || ProcessInfo.processInfo.environment["GLISSFORM_ANALYTICS_TEST"] == "1"
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(UsageAnalyticsState.self, from: data) {
            state = saved
        } else {
            // Inspect the persisted domain, not registered defaults. Sparkle and
            // saved settings distinguish existing installations on first migration.
            let old = defaults.persistentDomain(forName: bundle.bundleIdentifier ?? "") ?? [:]
            let known = ["animationStartAngle", "animationEnabled", "resumeAfterPause", "runInBackground",
                         "showMenuBarIcon", "automaticStartAngleEnabled", "SUHasLaunchedBefore",
                         "SULastCheckTime", "SUEnableAutomaticChecks", "licensePreview.v1"]
            let existing = known.contains { old[$0] != nil } || old[Self.storageKey] != nil
            state = UsageAnalyticsState(now: Date(), hasPreviousInstallation: existing)
        }
        // Only the local consent/onboarding state exists before opt-in; no ID or usage.
        save()
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 15
    }

    func choose(_ allowed: Bool) {
        generation += 1
        request?.cancel()
        request = nil
        session?.invalidateAndCancel()
        session = nil
        state.choose(allowed ? .allowed : .declined, at: Date())
        save()
        if allowed { tick(force: true) }
    }

    /// Called only when a real closing snapshot is first presented, never for
    /// sensor ticks, Settings previews, canceled captures or cached wake openings.
    func recordClose() { state.recordClose(at: Date()) }

    func checkpoint() { save() }

    func tick(force: Bool = false) {
        guard state.consent == .allowed else { return }
        state.tick(at: Date())
        save()
        guard force || Date().timeIntervalSince(lastAttempt) >= 300 else { return }
        flush()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        save()
        // Quit/sleep never waits for a network request. Unsent counts survive restart.
        request?.cancel()
        request = nil
        session?.invalidateAndCancel()
        session = nil
        generation += 1
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.storageKey) }
    }

    private func flush() {
        guard networkEnabled, state.consent == .allowed, request == nil, !state.pending.isEmpty else { return }
        let events = Array(state.pending.prefix(100))
        let formatter = ISO8601DateFormatter()
        let version = Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "development"
        let batch: [[String: Any]] = events.map { event in
            var properties: [String: Any] = [
                "environment": development ? "test" : "production", "platform": "macos", "schema_version": 1,
                "app_version": version, "$process_person_profile": false, "$geoip_disable": true, "$ip": "0.0.0.0"
            ]
            if let count = event.closeCount { properties["close_count"] = count }
            return ["event": event.name, "distinct_id": event.installationID,
                    "uuid": event.id.uuidString.lowercased(), "timestamp": formatter.string(from: event.day),
                    "properties": properties]
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["api_key": projectToken, "batch": batch]) else { return }
        if session == nil {
            let config = sessionConfiguration ?? URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCache = nil
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            session = URLSession(configuration: config)
        }
        var outgoing = URLRequest(url: URL(string: "https://eu.i.posthog.com/batch/")!)
        outgoing.httpMethod = "POST"
        outgoing.setValue("application/json", forHTTPHeaderField: "Content-Type")
        outgoing.httpBody = body
        let expectedGeneration = generation
        lastAttempt = Date()
        request = session?.dataTask(with: outgoing) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self, self.generation == expectedGeneration, self.state.consent == .allowed else { return }
                self.request = nil
                if error == nil, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) {
                    self.state.acknowledge(Set(events.map(\.id)))
                    self.save()
                }
            }
        }
        request?.resume()
    }
}
