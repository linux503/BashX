import AVFoundation

/// Lightweight procedural SFX for the disguise mini-game (no asset files).
final class GameSFX {
    static let shared = GameSFX()

    enum Event {
        case shoot, hit, pop, bigPop, leak, levelUp, wave, gameOver, start
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Event: AVAudioPCMBuffer] = [:]
    private var lastShootTime: CFTimeInterval = 0
    private var isReady = false

    private init() {
        prepare()
    }

    func play(_ event: Event, enabled: Bool) {
        guard enabled, isReady, let buffer = buffers[event] else { return }

        if event == .shoot {
            let now = CACurrentMediaTime()
            guard now - lastShootTime > 0.09 else { return }
            lastShootTime = now
        }

        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        buffers[.shoot] = tone(freq: 920, duration: 0.035, volume: 0.07)
        buffers[.hit] = tone(freq: 540, duration: 0.028, volume: 0.06)
        buffers[.pop] = pop(base: 680, sweep: -320, duration: 0.085, volume: 0.13)
        buffers[.bigPop] = pop(base: 460, sweep: -240, duration: 0.13, volume: 0.17)
        buffers[.leak] = tone(freq: 190, duration: 0.11, volume: 0.11)
        buffers[.levelUp] = arpeggio(freqs: [523, 659, 784], step: 0.09, volume: 0.11)
        buffers[.wave] = tone(freq: 760, duration: 0.075, volume: 0.09)
        buffers[.gameOver] = pop(base: 300, sweep: -180, duration: 0.22, volume: 0.14)
        buffers[.start] = arpeggio(freqs: [392, 523, 659], step: 0.07, volume: 0.1)

        try? engine.start()
        isReady = true
    }

    private func tone(freq: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            let env = exp(-t * 14)
            data[i] = Float(sin(2 * .pi * freq * t) * env) * volume
        }
        return buffer
    }

    private func pop(base: Double, sweep: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            let progress = t / duration
            let freq = base + sweep * progress
            let env = pow(1 - progress, 1.6)
            let click = sin(2 * .pi * freq * t) * env
            let noise = (Double.random(in: -1...1)) * env * 0.18
            data[i] = Float(click + noise) * volume
        }
        return buffer
    }

    private func arpeggio(freqs: [Double], step: Double, volume: Float) -> AVAudioPCMBuffer? {
        let duration = step * Double(freqs.count)
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            let idx = min(freqs.count - 1, Int(t / step))
            let localT = t - Double(idx) * step
            let freq = freqs[idx]
            let env = exp(-localT * 10)
            data[i] = Float(sin(2 * .pi * freq * localT) * env) * volume
        }
        return buffer
    }
}
