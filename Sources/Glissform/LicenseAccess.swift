import Foundation

/// Local preview policy. Production needs trusted trial records and signed entitlements.
struct LicenseAccess: Codable {
    static let trialDuration: TimeInterval = 3 * 24 * 60 * 60
    var trialStartedAt: Date?
    var lastSeenAt: Date?
    var licenseKey: String?
    var deviceID = UUID().uuidString

    mutating func observe(_ now: Date) {
        lastSeenAt = max(lastSeenAt ?? now, now)
    }

    mutating func startTrial(at now: Date) {
        observe(now)
        guard trialStartedAt == nil else { return }
        trialStartedAt = lastSeenAt
    }

    func remainingTrial(at now: Date) -> TimeInterval {
        guard let start = trialStartedAt else { return 0 }
        return max(0, Self.trialDuration - max(lastSeenAt ?? now, now).timeIntervalSince(start))
    }

    func allowsUse(at now: Date) -> Bool {
        licenseKey != nil || remainingTrial(at: now) > 0
    }

    func trialTimeLeft(at now: Date) -> String {
        let remaining = remainingTrial(at: now)
        guard remaining > 0 else { return "Trial ended" }
        if remaining >= 86400 {
            let days = Int(ceil(remaining / 86400))
            return days == 1 ? "1 day left" : "\(days) days left"
        }
        let hours = Int(remaining / 3600)
        if hours == 0 { return "Less than an hour left" }
        return hours == 1 ? "1 hour left" : "\(hours) hours left"
    }
}

struct LicenseReceipt: Codable {
    let key: String
    let devices: Int
    let limit: Int
}

struct CheckoutSession: Codable {
    let url: URL
}

/// The app deals with licensing, not a particular payment processor.
protocol LicenseService {
    func createCheckout() async throws -> CheckoutSession
    func activate(key: String, deviceID: String) async throws -> LicenseReceipt
    func deactivate(key: String, deviceID: String) async throws
}

struct PreviewLicenseService: LicenseService {
    private struct Failure: Decodable { let error: String }
    // Deliberately fixed to loopback. Public builds never enable this provider.
    static let baseURL = URL(string: "http://127.0.0.1:8765")!

    func createCheckout() async throws -> CheckoutSession {
        try await request("checkout", body: [:], as: CheckoutSession.self)
    }

    func activate(key: String, deviceID: String) async throws -> LicenseReceipt {
        try await request("activate", body: ["key": key, "device": deviceID], as: LicenseReceipt.self)
    }

    func deactivate(key: String, deviceID: String) async throws {
        let _: LicenseReceipt = try await request("deactivate", body: ["key": key, "device": deviceID], as: LicenseReceipt.self)
    }

    private func request<T: Decodable>(_ path: String, body: [String: String], as: T.Type) async throws -> T {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "The license service could not complete this request."
            throw NSError(domain: "GlissformLicense", code: response.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
