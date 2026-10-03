import Foundation

private enum TestError: Error { case failed(String), unavailable }
private func check(_ value: Bool, _ message: String) throws {
    if !value { throw TestError.failed(message) }
}

private actor FakeService: LicenseService {
    var devices = Set<String>()
    var offline = false
    func setOffline(_ value: Bool) { offline = value }
    func createCheckout() async throws -> CheckoutSession { throw TestError.unavailable }
    func activate(key: String, deviceID: String) async throws -> LicenseReceipt {
        if offline || key != "TEST-VALID" { throw TestError.unavailable }
        if !devices.contains(deviceID) && devices.count >= 1 { throw TestError.unavailable }
        devices.insert(deviceID)
        return LicenseReceipt(key: key, devices: devices.count, limit: 1)
    }
    func deactivate(key: String, deviceID: String) async throws {
        if offline { throw TestError.unavailable }
        devices.remove(deviceID)
    }
}

@main
struct LicenseChecks {
    @MainActor static func main() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = LicenseAccess()
        try check(!state.allowsUse(at: start), "An uninitialized trial has no entitlement")
        state.startTrial(at: start)
        for (elapsed, expected) in [(0.0, "3 days left"), (1.0, "3 days left"),
                                    (86400.0, "2 days left"), (172800.0, "1 day left"),
                                    (172801.0, "23 hours left"), (255600.0, "1 hour left"),
                                    (255601.0, "Less than an hour left"), (259200.0, "Trial ended")] {
            try check(state.trialTimeLeft(at: start.addingTimeInterval(elapsed)) == expected,
                      "Trial label must use the requested day/hour boundary at \(elapsed)")
        }
        state.startTrial(at: start.addingTimeInterval(300))
        try check(state.trialStartedAt == start, "Starting again must not renew trial")
        try check(state.allowsUse(at: start.addingTimeInterval(259199)), "Trial lasts 72 hours")
        try check(!state.allowsUse(at: start.addingTimeInterval(259200)), "Trial expires at 72 hours")
        state.observe(start.addingTimeInterval(259200))
        try check(!state.allowsUse(at: start), "Clock rollback must not restore an observed expired trial")
        let restored = try JSONDecoder().decode(LicenseAccess.self, from: JSONEncoder().encode(state))
        try check(restored.deviceID == state.deviceID && !restored.allowsUse(at: start), "Relaunch preserves device and expiry")

        let suite = "GlissformLicenseChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeService()
        let controller = LicenseController(isPreview: true, service: service, defaults: defaults)
        var changes: [Bool] = []
        controller.onAccessChange = { changes.append($0) }
        try check(controller.allowsUse && controller.access.trialStartedAt != nil, "First preview launch must start the trial automatically")
        let trialRelaunch = LicenseController(isPreview: true, service: service, defaults: defaults)
        try check(trialRelaunch.access.trialStartedAt == controller.access.trialStartedAt,
                  "Relaunch must preserve the original trial start")
        controller.expireTrial()
        try check(!controller.allowsUse && changes == [false], "Expiry must notify the renderer gate")
        await controller.activate("   ")
        await controller.activate("INVALID")
        try check(!controller.allowsUse && controller.message != nil, "Invalid keys must keep app locked")
        let expiredRelaunch = LicenseController(isPreview: true, service: service, defaults: defaults)
        try check(!expiredRelaunch.allowsUse, "Relaunch must not restart an expired trial")
        await controller.activate(" test-valid\n")
        try check(controller.allowsUse && changes.last == true, "Valid normalized key unlocks the app")
        let secondSuite = "GlissformLicenseChecks.\(UUID().uuidString)"
        let secondDefaults = UserDefaults(suiteName: secondSuite)!
        defer { secondDefaults.removePersistentDomain(forName: secondSuite) }
        let secondMac = LicenseController(isPreview: true, service: service, defaults: secondDefaults)
        secondMac.expireTrial()
        await secondMac.activate("TEST-VALID")
        try check(!secondMac.allowsUse && secondMac.access.licenseKey == nil,
                  "A second Mac must remain locked when this key is already active")
        let relaunched = LicenseController(isPreview: true, service: service, defaults: defaults)
        try check(relaunched.allowsUse && relaunched.access.deviceID == controller.access.deviceID, "Offline relaunch preserves activation")
        await service.setOffline(true)
        await controller.deactivate()
        try check(controller.allowsUse && controller.access.licenseKey != nil, "Failed deactivation must retain entitlement")
        await service.setOffline(false)
        await controller.deactivate()
        try check(!controller.allowsUse && changes.last == false, "Successful deactivation locks an expired trial")
        try check(!LicenseController(isPreview: true, service: service, defaults: defaults).allowsUse, "Deactivation persists")
        await secondMac.activate("TEST-VALID")
        try check(secondMac.allowsUse, "A deactivated key can move to another Mac")
        try check(!LicenseController.acceptsPreview(isDeveloperBuild: true, arguments: ["Glissform", "--license-preview"]),
                  "Free distribution must ignore old development preview shortcuts")
        let savedFixture = defaults.data(forKey: "licensePreview.v1")
        let freeMode = LicenseController(service: service, defaults: defaults)
        freeMode.expireTrial()
        freeMode.refresh(at: Date.distantFuture, force: true)
        await freeMode.buy()
        await freeMode.activate("TEST-VALID")
        await freeMode.deactivate()
        try check(!freeMode.isPreview && freeMode.allowsUse && freeMode.access.trialStartedAt == nil && freeMode.message == nil,
                  "Free mode ignores expired trials and all commerce operations")
        try check(defaults.data(forKey: "licensePreview.v1") == savedFixture,
                  "Free mode preserves dormant license data without updating it")
        let publicMode = LicenseController(isPreview: false, service: service, defaults: defaults)
        publicMode.expireTrial()
        await publicMode.activate("TEST-VALID")
        try check(publicMode.allowsUse && publicMode.access.licenseKey == nil, "Normal builds ignore preview state and operations")
        print("PASS: trial duration, rollback, persistence, activation, deactivation, offline failures and preview isolation")
    }
}
