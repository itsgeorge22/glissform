import AppKit
import SwiftUI

@MainActor
final class LicenseController: ObservableObject {
    // Product switch: keep the complete purchase UI for later, but make every
    // normal and development launch free, including old preview shortcuts.
    nonisolated static let previewsEnabled = false

    nonisolated static func acceptsPreview(isDeveloperBuild: Bool, arguments: [String]) -> Bool {
        previewsEnabled && isDeveloperBuild && arguments.contains("--license-preview")
    }

    nonisolated static var previewRequested: Bool {
        acceptsPreview(
            isDeveloperBuild: Bundle.main.object(forInfoDictionaryKey: "GlissformDeveloperTools") as? Bool == true,
            arguments: CommandLine.arguments
        )
    }

    let isPreview: Bool
    @Published private(set) var access: LicenseAccess
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var deviceCount: Int?
    @Published private(set) var now = Date()
    var onAccessChange: ((Bool) -> Void)?
    private let service: any LicenseService
    private let defaults: UserDefaults
    private let storageKey = "licensePreview.v1"
    private var lastAllowed: Bool

    init(isPreview: Bool = LicenseController.previewRequested,
         service: any LicenseService = PreviewLicenseService(), defaults: UserDefaults = .standard) {
        self.isPreview = isPreview
        self.service = service
        self.defaults = defaults
        let stored = isPreview ? defaults.data(forKey: storageKey) : nil
        var access = stored.flatMap { try? JSONDecoder().decode(LicenseAccess.self, from: $0) } ?? LicenseAccess()
        if isPreview {
            access.startTrial(at: Date())
            if let data = try? JSONEncoder().encode(access) { defaults.set(data, forKey: storageKey) }
        }
        self.access = access
        lastAllowed = !isPreview || access.allowsUse(at: Date())
    }

    var allowsUse: Bool { !isPreview || access.allowsUse(at: now) }
    var status: String {
        access.licenseKey == nil ? "Get Glissform" : "Glissform is activated"
    }

    func refresh(at date: Date = Date(), force: Bool = false) {
        guard isPreview else { return }
        guard force || abs(date.timeIntervalSince(now)) >= 60 || access.allowsUse(at: date) != lastAllowed else { return }
        now = date
        access.observe(date)
        saveAndNotify()
    }

    func buy() async {
        guard isPreview, !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let checkout = try await service.createCheckout()
            // Never trust an arbitrary redirect from the local service.
            guard checkout.url.scheme == "http", checkout.url.host == "127.0.0.1",
                  checkout.url.port == 8765, checkout.url.path.hasPrefix("/checkout/") else {
                throw URLError(.badURL)
            }
            guard NSWorkspace.shared.open(checkout.url) else { throw URLError(.cannotLoadFromNetwork) }
            message = "Finish the test checkout in your browser, then paste your key below."
        } catch { show(error) }
    }

    func activate(_ input: String) async {
        guard isPreview, !busy, access.licenseKey == nil else { return }
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { message = "Enter your license key."; return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let receipt = try await service.activate(key: key, deviceID: access.deviceID)
            guard receipt.key == key, receipt.limit == 1, receipt.devices == 1 else {
                throw URLError(.cannotParseResponse)
            }
            access.licenseKey = receipt.key
            deviceCount = receipt.devices
            refresh(force: true)
            message = "Lifetime access activated on this Mac."
        } catch { show(error) }
    }

    func deactivate() async {
        guard isPreview, !busy, let key = access.licenseKey else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await service.deactivate(key: key, deviceID: access.deviceID)
            access.licenseKey = nil
            deviceCount = nil
            refresh(force: true)
            message = "This Mac has been deactivated. Its slot is available for another Mac."
        } catch { show(error) }
    }

    /// Only reachable in the explicitly enabled development preview.
    func expireTrial() {
        guard isPreview, !busy, access.licenseKey == nil else { return }
        access.trialStartedAt = Date().addingTimeInterval(-LicenseAccess.trialDuration)
        refresh(force: true)
    }

    private func saveAndNotify() {
        if let data = try? JSONEncoder().encode(access) { defaults.set(data, forKey: storageKey) }
        let allowed = allowsUse
        if allowed != lastAllowed {
            lastAllowed = allowed
            onAccessChange?(allowed)
        }
    }

    private func show(_ error: Error) {
        if (error as NSError).domain == NSURLErrorDomain {
            message = "Couldn’t reach the local checkout. Start the preview server and try again."
        } else { message = error.localizedDescription }
    }
}
