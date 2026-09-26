import AVFoundation
import Foundation

/// Keep audio setup and playback away from the main run loop that renders lid motion.
final class PauseRestorationSound: @unchecked Sendable {
    static let shared = PauseRestorationSound()

    private let queue = DispatchQueue(label: "app.glissform.return-sound", qos: .userInitiated)
    // Accessed only on queue.
    private var player: AVAudioPlayer?
    private var didAttemptLoad = false

    func prepare() {
        queue.async {
            guard let player = self.loadPlayer() else { return }
            // A completed click releases the player's prepared audio resources.
            _ = player.prepareToPlay()
        }
    }

    func play() {
        queue.async {
            guard let player = self.loadPlayer() else { return }
            player.currentTime = 0
            _ = player.play()
        }
    }

    private func loadPlayer() -> AVAudioPlayer? {
        if didAttemptLoad { return player }
        didAttemptLoad = true
        guard let url = Bundle.module.url(forResource: "PauseRestored", withExtension: "wav"),
              let loaded = try? AVAudioPlayer(contentsOf: url) else { return nil }
        loaded.volume = 0.4
        player = loaded
        return loaded
    }
}
