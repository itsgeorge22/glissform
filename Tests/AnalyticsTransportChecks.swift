import Foundation

// Every request is intercepted locally. These checks never contact PostHog.
private final class AnalyticsProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var bodies: [Data] = []
    static var status = 503
    static var hold = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock()
        Self.requests.append(request)
        Self.bodies.append(body)
        let status = Self.status
        let hold = Self.hold
        Self.lock.unlock()
        guard !hold else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    static func payloads() -> [Data] { lock.lock(); defer { lock.unlock() }; return bodies }
    static func respond(_ status: Int, hold: Bool = false) {
        lock.lock(); defer { lock.unlock() }; self.status = status; self.hold = hold
    }
}

@main
struct AnalyticsTransportChecks {
    @MainActor static func main() async throws {
        let suite = "Glissform.AnalyticsChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnalyticsProtocol.self]
        let analytics = UsageAnalytics(defaults: defaults, sessionConfiguration: config)
        analytics.start()
        analytics.recordClose()
        analytics.tick(force: true)
        precondition(AnalyticsProtocol.snapshot().isEmpty, "No request before consent")
        analytics.choose(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(AnalyticsProtocol.snapshot().count == 1)
        let pending = analytics.state.pending.map(\.id)
        precondition(!pending.isEmpty, "Failed requests retain events")
        AnalyticsProtocol.respond(200)
        analytics.tick(force: true)
        for _ in 0..<100 where !analytics.state.pending.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(analytics.state.pending.isEmpty, "A successful retry acknowledges the batch")
        let sent = AnalyticsProtocol.snapshot()
        precondition(sent.count == 2 && sent[0].url?.host == "eu.i.posthog.com")
        let bodies = AnalyticsProtocol.payloads()
        let payload = try JSONSerialization.jsonObject(with: bodies[0]) as! NSDictionary
        let retry = try JSONSerialization.jsonObject(with: bodies[1]) as! NSDictionary
        precondition(payload == retry, "Retries preserve event IDs and payloads")
        let batch = payload["batch"] as! [[String: Any]]
        let properties = batch[0]["properties"] as! [String: Any]
        precondition(properties["environment"] as? String == "test")
        precondition(properties["$process_person_profile"] as? Bool == false)
        precondition(properties["$geoip_disable"] as? Bool == true)
        AnalyticsProtocol.respond(200, hold: true)
        analytics.recordClose()
        analytics.tick(force: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        analytics.choose(false)
        let count = AnalyticsProtocol.snapshot().count
        analytics.recordClose()
        analytics.tick(force: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(AnalyticsProtocol.snapshot().count == count)
        precondition(analytics.state.pending.isEmpty && analytics.state.installationID == nil)
        analytics.stop()
        let restarted = UsageAnalytics(defaults: defaults, sessionConfiguration: config)
        precondition(restarted.state.consent == .declined && restarted.state.installationID == nil)
        print("PASS: analytics network consent gate, failed retry, stable payload, acknowledgement, withdrawal and persisted choice")
    }
}
