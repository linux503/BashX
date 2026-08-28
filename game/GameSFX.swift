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

        buffers[.shoot] = softLaser(volume: 0.11)
        buffers[.hit] = tone(freq: 540, duration: 0.028, volume: 0.06)
        buffers[.pop] = pop(base: 680, sweep: -320, duration: 0.085, volume: 0.13)
        buffers[.bigPop] = pop(base: 460, sweep: -240, duration: 0.13, volume: 0.17)
        buffers[.leak] = tone(freq: 190, duration: 0.11, volume: 0.11)
        buffers[.levelUp] = arpeggio(freqs: [523, 659, 784], step: 0.09, volume: 0.11)
        buffers[.wave] = tone(freq: 760, duration: 0.075, volume: 0.09)
        buffers[.gameOver] = pop(base: 300, sweep: -180, duration: 0.22, volume: 0.14)
        // Soft major sparkle on enter — C5→E5→G5→C6 with gentle pad underneath.
        buffers[.start] = startChime(volume: 0.14)

        try? engine.start()
        isReady = true
    }

    private func softLaser(volume: Float) -> AVAudioPCMBuffer? {
        let duration = 0.095
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            let progress = t / duration
            let freq = 660 * pow(0.58, progress)
            let env = pow(1 - progress, 1.15) * (0.35 + 0.65 * sin(.pi * min(1, progress * 1.8)))
            let fund = sin(2 * .pi * freq * t)
            let harm = 0.28 * sin(2 * .pi * freq * 2.0 * t)
            let air = 0.08 * sin(2 * .pi * freq * 3.0 * t) * (1 - progress)
            data[i] = Float((fund + harm + air) * env) * volume
        }
        return buffer
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

    /// Warm entry chime: soft sine arpeggio + quiet fifth pad (less harsh than raw beeps).
    private func startChime(volume: Float) -> AVAudioPCMBuffer? {
        let notes: [(freq: Double, at: Double, dur: Double)] = [
            (523.25, 0.00, 0.28), // C5
            (659.25, 0.09, 0.28), // E5
            (783.99, 0.18, 0.32), // G5
            (1046.5, 0.28, 0.42), // C6
        ]
        let duration = 0.72
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        for i in 0..<Int(frameCount) {
            let t = Double(i) / format.sampleRate
            var sample = 0.0
            // Soft pad under the arpeggio (C + G)
            let padEnv = min(1.0, t / 0.05) * exp(-t * 2.2)
            sample += sin(2 * .pi * 261.63 * t) * padEnv * 0.18
            sample += sin(2 * .pi * 392.00 * t) * padEnv * 0.12
            for note in notes {
                let local = t - note.at
                guard local >= 0, local <= note.dur else { continue }
                let attack = min(1.0, local / 0.012)
                let env = attack * exp(-local * 5.5)
                // Fundamental + soft octave harmonic
                sample += sin(2 * .pi * note.freq * local) * env * 0.55
                sample += sin(2 * .pi * note.freq * 2 * local) * env * 0.12
            }
            // Gentle soft-clip
            sample = tanh(sample * 1.15)
            data[i] = Float(sample) * volume
        }
        return buffer
    }
}
