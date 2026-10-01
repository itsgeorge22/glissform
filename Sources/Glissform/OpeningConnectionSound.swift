import AVFoundation
import Foundation
import OSLog

@MainActor protocol ConnectionSoundPlayback: AnyObject {
    func prepare()
    func schedule(peakAt time: Double, completion: @escaping @MainActor (Double?) -> Void)
    func finish()
    func stop()
}

/// Warms output only during a gesture, then schedules the sample's peak against
/// the same host clock as the display. It never opens an audio input.
@MainActor final class OpeningConnectionSound: ConnectionSoundPlayback {
    static let shared = OpeningConnectionSound()
    private let output = Output()

    func prepare() { output.prepare() }
    func schedule(peakAt time: Double, completion: @escaping @MainActor (Double?) -> Void) {
        output.schedule(peakAt: time, completion: completion)
    }
    func finish() { output.finish() }
    func stop() { output.stop() }

    private final class Output: @unchecked Sendable {
        private let queue = DispatchQueue(label: "app.glissform.connection-sound", qos: .userInitiated)
        private let log = Logger(subsystem: "com.george.glissform.mvp", category: "ConnectionSound")
        // Invalidated immediately, even if starting the output blocks its queue.
        private let lock = NSLock()
        private var generation = 0
        // The remaining state belongs exclusively to queue.
        private var engine: AVAudioEngine?
        private var player: AVAudioPlayerNode?
        private var buffer: AVAudioPCMBuffer?
        private var samplePeak = 0.0
        private var scheduled = false
        private var retiring = false
        private var cue = 0

        private func token() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
        private func invalidate() { lock.lock(); generation += 1; lock.unlock() }

        func prepare() {
            let token = token()
            queue.async {
                guard self.token() == token else { return }
                self.retiring = false
                do { try self.startOutput() }
                catch { self.log.error("Could not prepare connection audio: \(error.localizedDescription, privacy: .public)") }
                if self.token() != token { self.stopOutput() }
            }
        }

        func schedule(peakAt requestedPeak: Double, completion: @escaping @MainActor (Double?) -> Void) {
            let token = token()
            queue.async { [self] in
                guard self.token() == token else { return }
                do {
                    try self.startOutput()
                    guard self.token() == token, let player = self.player, let buffer = self.buffer else { return }
                    self.cue += 1
                    let cue = self.cue
                    self.scheduled = true
                    self.retiring = false
                    player.stop()
                    // Re-read after engine startup: a route change can alter this.
                    let latency = player.outputPresentationLatency
                    let plan = ConnectionFeedbackTiming.playback(requestedPeak: requestedPeak,
                        now: ProcessInfo.processInfo.systemUptime, latency: latency, samplePeak: self.samplePeak)
                    player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        // Never stop a player on its render/completion thread.
                        self?.queue.async { [weak self] in
                            guard let self, self.token() == token, self.cue == cue else { return }
                            self.log.info("Connection sample finished playing")
                            self.scheduled = false
                            if self.retiring { self.stopOutput() }
                        }
                    }
                    player.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: plan.renderStart)))
                    self.log.info("Scheduled peak: latencyMs=\(latency * 1000), adjustmentMs=\((plan.audiblePeak - requestedPeak) * 1000)")
                    DispatchQueue.main.async {
                        guard self.token() == token else { return }
                        completion(plan.audiblePeak)
                    }
                } catch {
                    self.log.error("Could not schedule connection audio: \(error.localizedDescription, privacy: .public)")
                    self.stopOutput()
                    DispatchQueue.main.async {
                        guard self.token() == token else { return }
                        completion(nil)
                    }
                }
            }
        }

        func finish() {
            queue.async {
                self.retiring = true
                if !self.scheduled { self.stopOutput() }
                else {
                    // A lost device callback must not keep output alive forever.
                    let cue = self.cue
                    self.queue.asyncAfter(deadline: .now() + 1) {
                        guard self.cue == cue, self.retiring else { return }
                        self.stopOutput()
                    }
                }
            }
        }

        func stop() {
            invalidate()
            queue.async { self.stopOutput() }
        }

        private func stopOutput() {
            cue += 1
            scheduled = false
            player?.stop()
            engine?.stop()
        }

        private func startOutput() throws {
            if buffer == nil {
                guard let url = AppResource.url("PauseRestored", extension: "wav") else {
                    throw NSError(domain: "Glissform.ConnectionSound", code: 1)
                }
                let file = try AVAudioFile(forReading: url)
                guard let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)) else {
                    throw NSError(domain: "Glissform.ConnectionSound", code: 2)
                }
                try file.read(into: loaded)
                guard let channels = loaded.floatChannelData, loaded.frameLength > 0 else {
                    throw NSError(domain: "Glissform.ConnectionSound", code: 3)
                }
                var maximum: Float = 0
                var peakFrame = 0
                for channel in 0..<Int(loaded.format.channelCount) {
                    for frame in 0..<Int(loaded.frameLength) {
                        let amplitude = abs(channels[channel][frame * loaded.stride])
                        if amplitude > maximum { maximum = amplitude; peakFrame = frame }
                    }
                }
                samplePeak = Double(peakFrame) / loaded.format.sampleRate
                buffer = loaded
            }
            if engine == nil, let buffer {
                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                player.volume = 0.4
                self.engine = engine
                self.player = player
            }
            if let engine, !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        }
    }
}
