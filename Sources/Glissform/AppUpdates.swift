import Foundation
import Sparkle

@MainActor
final class AppUpdates: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let model: SettingsModel
    private var controller: SPUStandardUpdaterController!
    private var automaticUpdateObservation: NSKeyValueObservation?

    init(model: SettingsModel) {
        self.model = model
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: self)
        automaticUpdateObservation = controller.updater.observe(\.automaticallyDownloadsUpdates,
                                                               options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.model.syncAutomaticUpdatesEnabled(updater.automaticallyDownloadsUpdates)
            }
        }
        model.onAutomaticUpdatesEnabledChange = { [weak self] enabled in
            self?.controller.updater.automaticallyDownloadsUpdates = enabled
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? ""
        return version.contains("-") ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        showManualUpdateIfNeeded(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        model.setAvailableUpdate(nil)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                           andInImmediateFocus immediateFocus: Bool) -> Bool {
        MainActor.assumeIsolated { model.automaticUpdatesEnabled }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                model.setAvailableUpdate(nil)
            } else {
                showManualUpdateIfNeeded(update)
            }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { model.setAvailableUpdate(nil) }
    }

    private func showManualUpdateIfNeeded(_ item: SUAppcastItem) {
        guard !model.automaticUpdatesEnabled else {
            model.setAvailableUpdate(nil)
            return
        }
        model.setAvailableUpdate(.init(version: item.displayVersionString,
                                       install: { [weak self] in self?.checkForUpdates() }))
    }
}
