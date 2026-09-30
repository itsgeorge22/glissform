import AVFoundation
import Foundation

/// Plays the short, previously used desktop-return click without blocking lid rendering.
final class OpeningConnectionSound: @unchecked Sendable {
    static let shared = OpeningConnectionSound()

    private let queue = DispatchQueue(label: "app.glissform.opening-connection-sound", qos: .userInitiated)
    // Accessed only on queue.
    private var player: AVAudioPlayer?
    private var didAttemptLoad = false

    func prepare() {
        queue.async {
            guard let player = self.loadPlayer() else { return }
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

    func stop() {
        queue.async {
            self.player?.stop()
            self.player?.currentTime = 0
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
