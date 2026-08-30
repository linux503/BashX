import AVFoundation

/// Procedural orchard-arcade SFX — fixed slot pool, no per-play buffer allocation.
final class GameSFX {
    static let shared = GameSFX()

    enum Event: Hashable {
        case shoot, hit, pop, bigPop, boom, leak, levelUp, wave, gameOver, start
    }

    private struct Slot {
        let buffer: AVAudioPCMBuffer
        var busy = false
    }

    private let engine = AVAudioEngine()
    private let shootPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var fxPools: [Event: [AVAudioPCMBuffer]] = [:]
    private var fxPoolCursor: [Event: Int] = [:]
    private var weaponPools: [GameProgression.WeaponStyle: [AVAudioPCMBuffer]] = [:]
    private var weaponPoolCursor: [GameProgression.WeaponStyle: Int] = [:]
    private var shootFallback: [AVAudioPCMBuffer] = []
    private var shootFallbackCursor = 0
    private var shootSlots: [Slot] = []
    private var fxSlots: [Slot] = []
    private var lastShootTime: CFTimeInterval = 0
    private var isReady = false
    private var lastHitTime: CFTimeInterval = 0

    private let shootSlotCount = 10
    private let fxSlotCount = 10
    private let maxShootFrames: AVAudioFrameCount = 5_400   // ~0.12s
    private let maxFXFrames: AVAudioFrameCount = 5_000      // ~0.11s

    private init() {}

    func play(_ event: Event, enabled: Bool) {
        guard enabled else { return }
        if event == .hit {
            let now = CACurrentMediaTime()
            guard now - lastHitTime > 0.08 else { return }
            lastHitTime = now
        }
        ensureReady()
        guard isReady, let buffer = nextFXBuffer(event) else { return }
        scheduleFX(buffer)
    }

    func playShoot(weapon: GameProgression.WeaponStyle, stageIndex: Int, enabled: Bool) {
        guard enabled else { return }
        ensureReady()
        guard isReady else { return }

        let minGap: CFTimeInterval = {
            switch weapon {
            case .rail, .missile, .nova: return 0.09
            case .spread, .prism: return 0.075
            default: return 0.058
            }
        }()
        let now = CACurrentMediaTime()
        guard now - lastShootTime > minGap else { return }
        lastShootTime = now

        let buffer = nextWeaponBuffer(weapon) ?? nextShootFallback()
        guard let buffer else { return }
        scheduleShoot(buffer)
        _ = stageIndex
    }

    private func ensureReady() {
        guard !isReady else { return }
        prepare()
    }

    private func nextFXBuffer(_ event: Event) -> AVAudioPCMBuffer? {
        guard let pool = fxPools[event], !pool.isEmpty else { return nil }
        let idx = fxPoolCursor[event, default: 0] % pool.count
        fxPoolCursor[event] = idx + 1
        return pool[idx]
    }

    private func nextWeaponBuffer(_ weapon: GameProgression.WeaponStyle) -> AVAudioPCMBuffer? {
        guard let pool = weaponPools[weapon], !pool.isEmpty else { return nil }
        let idx = weaponPoolCursor[weapon, default: 0] % pool.count
        weaponPoolCursor[weapon] = idx + 1
        return pool[idx]
    }

    private func nextShootFallback() -> AVAudioPCMBuffer? {
        guard !shootFallback.isEmpty else { return nil }
        let idx = shootFallbackCursor % shootFallback.count
        shootFallbackCursor += 1
        return shootFallback[idx]
    }

    private func scheduleShoot(_ buffer: AVAudioPCMBuffer) {
        guard let slotIndex = acquireSlotIndex(in: &shootSlots, minFrames: buffer.frameLength) else { return }
        let dst = shootSlots[slotIndex].buffer
        guard copyPCM(from: buffer, to: dst) else {
            shootSlots[slotIndex].busy = false
            return
        }
        guard startEngineIfNeeded() else {
            shootSlots[slotIndex].busy = false
            return
        }
        shootPlayer.scheduleBuffer(dst, at: nil, options: .interrupts) { [weak self] in
            self?.releaseShootSlot(slotIndex)
        }
        if !shootPlayer.isPlaying { shootPlayer.play() }
    }

    private func scheduleFX(_ buffer: AVAudioPCMBuffer) {
        guard let slotIndex = acquireSlotIndex(in: &fxSlots, minFrames: buffer.frameLength) else { return }
        let dst = fxSlots[slotIndex].buffer
        guard copyPCM(from: buffer, to: dst) else {
            fxSlots[slotIndex].busy = false
            return
        }
        guard startEngineIfNeeded() else {
            fxSlots[slotIndex].busy = false
            return
        }
        fxPlayer.scheduleBuffer(dst, at: nil, options: []) { [weak self] in
            self?.releaseFXSlot(slotIndex)
        }
        if !fxPlayer.isPlaying { fxPlayer.play() }
    }

    private func acquireSlotIndex(in slots: inout [Slot], minFrames: AVAudioFrameCount) -> Int? {
        for i in slots.indices where !slots[i].busy && slots[i].buffer.frameCapacity >= minFrames {
            slots[i].busy = true
            return i
        }
        return nil
    }

    private func releaseShootSlot(_ index: Int) {
        guard shootSlots.indices.contains(index) else { return }
        shootSlots[index].busy = false
    }

    private func releaseFXSlot(_ index: Int) {
        guard fxSlots.indices.contains(index) else { return }
        fxSlots[index].busy = false
    }

    private func copyPCM(from src: AVAudioPCMBuffer, to dst: AVAudioPCMBuffer) -> Bool {
        guard src.frameLength > 0,
              dst.frameCapacity >= src.frameLength,
              let s = src.floatChannelData?[0],
              let d = dst.floatChannelData?[0] else { return false }
        dst.frameLength = src.frameLength
        memcpy(d, s, Int(src.frameLength) * MemoryLayout<Float>.size)
        return true
    }

    /// Drop stuck slots if completion handlers lag behind.
    func recoverIfNeeded() {
        guard isReady else { return }
        let stuckShoot = shootSlots.filter(\.busy).count
        let stuckFX = fxSlots.filter(\.busy).count
        if stuckShoot >= shootSlotCount - 1 {
            shootPlayer.stop()
            for i in shootSlots.indices { shootSlots[i].busy = false }
        }
        if stuckFX >= fxSlotCount - 1 {
            fxPlayer.stop()
            for i in fxSlots.indices { fxSlots[i].busy = false }
        }
    }

    private func startEngineIfNeeded() -> Bool {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false
            }
        }
        return true
    }

    private func prepare() {
        guard !isReady else { return }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        format = fmt

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(shootPlayer)
        engine.attach(fxPlayer)
        engine.connect(shootPlayer, to: engine.mainMixerNode, format: fmt)
        engine.connect(fxPlayer, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.88

        shootSlots = makeSlots(count: shootSlotCount, frameCapacity: maxShootFrames, format: fmt)
        fxSlots = makeSlots(count: fxSlotCount, frameCapacity: maxFXFrames, format: fmt)

        shootFallback = makePool(count: 3) { softPew(volume: 0.088) }
        for weapon in GameProgression.WeaponStyle.allCases {
            weaponPools[weapon] = makePool(count: 3) { weaponShot(weapon, volume: shotVolume(for: weapon)) }
        }

        fxPools[.shoot] = shootFallback
        fxPools[.hit] = makePool(count: 4) { softTick(volume: 0.055) }
        fxPools[.pop] = makePool(count: 4) { bubblePop(base: 520, sweep: -280, duration: 0.1, volume: 0.12) }
        fxPools[.bigPop] = makePool(count: 3) { bubblePop(base: 360, sweep: -180, duration: 0.14, volume: 0.15) }
        fxPools[.boom] = makePool(count: 3) { softBoom(duration: 0.16, volume: 0.16) }
        fxPools[.leak] = makePool(count: 2) { softWarn(volume: 0.1) }
        fxPools[.levelUp] = makePool(count: 2) { orchardWin(volume: 0.11) }
        fxPools[.wave] = makePool(count: 2) { waveChime(volume: 0.085) }
        fxPools[.gameOver] = makePool(count: 2) { softFail(volume: 0.12) }
        fxPools[.start] = makePool(count: 2) { orchardStart(volume: 0.1) }

        do {
            try engine.start()
            isReady = true
        } catch {
            isReady = false
        }
    }

    private func makeSlots(count: Int, frameCapacity: AVAudioFrameCount, format: AVAudioFormat) -> [Slot] {
        (0..<count).compactMap { _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
            return Slot(buffer: buffer)
        }
    }

    private func makePool(count: Int, _ builder: () -> AVAudioPCMBuffer?) -> [AVAudioPCMBuffer] {
        (0..<count).compactMap { _ in builder() }
    }

    private func shotVolume(for weapon: GameProgression.WeaponStyle) -> Float {
        switch weapon {
        case .pulse, .twin: return 0.085
        case .spread, .prism: return 0.078
        case .rail, .plasma: return 0.092
        case .missile, .nova: return 0.098
        }
    }

    // MARK: - Soft orchard palette

    private func weaponShot(_ weapon: GameProgression.WeaponStyle, volume: Float) -> AVAudioPCMBuffer? {
        switch weapon {
        case .pulse: return softPew(volume: volume)
        case .twin: return twinPew(volume: volume)
        case .spread: return scatterPew(volume: volume)
        case .rail: return railThump(volume: volume)
        case .plasma: return plasmaWobble(volume: volume)
        case .missile: return missileWhoosh(volume: volume)
        case .prism: return prismChime(volume: volume)
        case .nova: return novaBloom(volume: volume)
        }
    }

    private func softPew(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.065) { t, progress, _ in
            let env = min(1, progress / 0.01) * pow(1 - progress, 1.35)
            let f = 480.0 * pow(0.82, progress)
            let tone = sin(2 * .pi * f * t) * 0.62 + sin(2 * .pi * f * 2.0 * t) * 0.12
            return Float(tone * env) * volume
        }
    }

    private func twinPew(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.09) { t, _, _ in
            let a = pewPulse(t: t, start: 0, width: 0.04, freq: 560)
            let b = pewPulse(t: t, start: 0.042, width: 0.038, freq: 680)
            return softClip((a + b) * 0.75) * volume
        }
    }

    private func scatterPew(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.08) { t, progress, _ in
            let env = pow(1 - progress, 1.5)
            let ping = sin(2 * .pi * (740 - progress * 320) * t) * env * 0.42
            let sparkle = sin(2 * .pi * 1180 * t) * env * 0.12 * (1 - progress)
            return Float(ping + sparkle) * volume
        }
    }

    private func railThump(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.1) { t, progress, _ in
            let env = pow(1 - progress, 1.05)
            let low = sin(2 * .pi * (95 + progress * 40) * t) * 0.48
            let zip = sin(2 * .pi * (1200 - progress * 900) * t) * 0.22 * (1 - progress * 0.7)
            return Float((low + zip) * env) * volume
        }
    }

    private func plasmaWobble(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.09) { t, progress, _ in
            let env = min(1, progress / 0.012) * pow(1 - progress, 1.15)
            let wob = 210 + sin(t * 32) * 38
            let core = sin(2 * .pi * wob * t) * 0.46
            return Float(core * env) * volume
        }
    }

    private func missileWhoosh(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.11) { t, progress, _ in
            let env = pow(1 - progress, 0.95)
            let sweep = 760.0 - progress * 480.0
            return Float(sin(2 * .pi * sweep * t) * env * 0.4) * volume
        }
    }

    private func prismChime(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.095) { t, progress, _ in
            let env = min(1, progress / 0.008) * pow(1 - progress, 1.3)
            let c1 = sin(2 * .pi * 784 * t) * 0.32
            let c2 = sin(2 * .pi * 988 * t) * 0.24 * max(0, 1 - progress)
            return Float((c1 + c2) * env) * volume
        }
    }

    private func novaBloom(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.12) { t, progress, _ in
            let env = min(1, progress / 0.018) * pow(1 - progress, 0.82)
            let body = sin(2 * .pi * (80 + progress * 50) * t) * 0.34
            let flare = sin(2 * .pi * (420 + progress * 220) * t) * 0.26 * (1 - progress)
            return Float((body + flare) * env) * volume
        }
    }

    private func softTick(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.028) { t, _, _ in
            let env = exp(-t * 18)
            return Float(sin(2 * .pi * 660 * t) * env * 0.55) * volume
        }
    }

    private func bubblePop(base: Double, sweep: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: duration) { t, progress, _ in
            let freq = base + sweep * progress
            let env = pow(1 - progress, 1.45)
            let body = sin(2 * .pi * freq * t) * env * 0.58
            let plip = sin(2 * .pi * (freq * 1.5) * t) * env * 0.14
            return Float((body + plip) * env) * volume
        }
    }

    private func softBoom(duration: Double, volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: duration) { t, progress, _ in
            let env = pow(1 - progress, 1.2)
            let thump = sin(2 * .pi * (130 - progress * 70) * t) * env * 0.5
            let ring = sin(2 * .pi * (300 + progress * 180) * t) * env * 0.22
            return Float(thump + ring) * volume
        }
    }

    private func softWarn(volume: Float) -> AVAudioPCMBuffer? {
        synth(duration: 0.14) { t, progress, _ in
            let env = min(1, progress / 0.02) * pow(1 - progress, 0.85)
            let a = sin(2 * .pi * 330 * t) * max(0, 1 - progress * 1.8)
            let b = sin(2 * .pi * 260 * t) * max(0, progress - 0.4)
            return Float((a + b) * env * 0.55) * volume
        }
    }

    private func orchardWin(volume: Float) -> AVAudioPCMBuffer? {
        melody(notes: [523, 659, 784, 988], step: 0.08, volume: volume)
    }

    private func waveChime(volume: Float) -> AVAudioPCMBuffer? {
        melody(notes: [440, 554, 659], step: 0.07, volume: volume)
    }

    private func softFail(volume: Float) -> AVAudioPCMBuffer? {
        melody(notes: [330, 294, 262, 220], step: 0.1, volume: volume, descending: true)
    }

    private func orchardStart(volume: Float) -> AVAudioPCMBuffer? {
        melody(notes: [392, 494, 587, 698], step: 0.065, volume: volume)
    }

    private func melody(notes: [Double], step: Double, volume: Float, descending: Bool = false) -> AVAudioPCMBuffer? {
        let ordered = descending ? notes : notes
        let duration = step * Double(ordered.count) + 0.05
        return synth(duration: duration) { t, progress, _ in
            let idx = min(ordered.count - 1, Int(t / step))
            let localT = t - Double(idx) * step
            let freq = ordered[idx]
            let env = exp(-localT * 8) * pow(1 - progress, 0.4)
            let tone = sin(2 * .pi * freq * localT) * env
            let bell = sin(2 * .pi * freq * 2.02 * localT) * env * 0.15
            return Float(tone + bell) * volume
        }
    }

    private func pewPulse(t: Double, start: Double, width: Double, freq: Double) -> Float {
        guard t >= start, t < start + width else { return 0 }
        let local = (t - start) / width
        let env = min(1, local / 0.18) * pow(1 - local, 1.25)
        return Float(sin(2 * .pi * freq * t) * env)
    }

    private func synth(
        duration: Double,
        _ sample: (_ t: Double, _ progress: Double, _ sampleRate: Double) -> Float
    ) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let sr = format.sampleRate
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sr
            let progress = t / duration
            data[i] = softClip(sample(t, progress, sr))
        }
        return buffer
    }

    private func softClip(_ x: Float) -> Float {
        tanh(max(-1.2, min(1.2, x)) * 1.05)
    }
}
