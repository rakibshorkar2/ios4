import AVFoundation
import UIKit

class BackgroundAudioService {
    static let shared = BackgroundAudioService()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var isActive = false

    func start() {
        guard !isActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
            buffer.frameLength = buffer.frameCapacity
            let channelData = buffer.floatChannelData![0]
            memset(channelData, 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            player.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            player.play()

            self.engine = engine
            self.player = player
            isActive = true
        } catch {
            print("[BackgroundAudio] Failed to start: \(error)")
        }
    }

    func stop() {
        guard isActive else { return }
        player?.stop()
        engine?.stop()
        if let p = player { engine?.detach(p) }
        player = nil
        engine = nil
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
