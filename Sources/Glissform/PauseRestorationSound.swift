import AppKit

@MainActor
final class PauseRestorationSound {
    static let shared = PauseRestorationSound()

    private let sound: NSSound?

    private init() {
        guard let url = Bundle.module.url(forResource: "PauseRestored", withExtension: "wav") else {
            sound = nil
            return
        }
        let loaded = NSSound(contentsOf: url, byReference: false)
        loaded?.volume = 0.4
        sound = loaded
    }

    func play() {
        guard let sound else { return }
        if sound.isPlaying { _ = sound.stop() }
        sound.currentTime = 0
        _ = sound.play()
    }
}
