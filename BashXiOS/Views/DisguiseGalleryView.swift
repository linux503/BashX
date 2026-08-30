import SwiftUI
import UIKit

/// Camouflage fruit-defense arcade (orchard theme).
/// Unlock: tap the tip card above Start 5 times.
struct DisguiseGalleryView: View {
    var onUnlocked: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var bubbles: [GameBubble] = []
    @State private var motionFrame = 0
    @State private var shots: [LaserShot] = []
    @State private var shards: [ShatterShard] = []
    @State private var ripples: [PopRipple] = []
    @State private var blasts: [BlastFX] = []
    @State private var floatTexts: [FloatText] = []
    @State private var score = 0
    @State private var brokenTotal = UserDefaults.standard.integer(forKey: Keys.broken)
    @State private var highScore = UserDefaults.standard.integer(forKey: Keys.high)
    @State private var careerScore = UserDefaults.standard.integer(forKey: Keys.careerScore)
    @State private var combo = 0
    @State private var maxUnlockedStage = 0
    @State private var playingStage = 0
    @State private var killsThisRun = 0
    @State private var lives = 3
    /// Miss buffer before a heart drops — keeps early mistakes fun.
    @State private var leakShield = 3
    @State private var waveStage = 0
    @State private var isPlaying = false
    @State private var showSettings = false
    @State private var hapticsOn = true
    @State private var soundOn = UserDefaults.standard.object(forKey: Keys.sound) as? Bool ?? true
    @State private var shipX: CGFloat = 0
    @State private var shipY: CGFloat = 0
    @State private var shipReady = false
    @State private var spawnTask: Task<Void, Never>?
    @State private var motionTask: Task<Void, Never>?
    @State private var fireTask: Task<Void, Never>?
    @State private var unlockTriggered = false
    @State private var unlockTapCount = 0
    @State private var unlockTapResetTask: Task<Void, Never>?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var stageClearHandled = false
    @State private var stageCelebrating = false
    @State private var stageClearSnapshot: StageClearSnapshot?
    @State private var stageClearProgress: CGFloat = 0
    @State private var stageClearTask: Task<Void, Never>?
    @State private var maxComboThisRun = 0
    @State private var cleanKillStreak = 0
    @State private var activeBonus: PlayBonus = .none
    @State private var bonusTimer: CGFloat = 0
    @State private var playSize: CGSize = .zero
    @State private var layout = GameLayoutMetrics.default
    @State private var playTop: CGFloat = 120
    @State private var playBottom: CGFloat = 120
    @State private var stars: [StarDust] = []
    @State private var thrustPhase: CGFloat = 0
    @State private var levelFlash = false
    @State private var leakFlash = false
    @State private var fireJammedUntil: Date = .distantPast
    @State private var startPulse = false
    @State private var pausedByBackground = false
    @State private var skyBreath = false
    @State private var cloudDrift: CGFloat = 0
    @State private var petalSpin: Double = 0
    @State private var sunPulse = false
    @State private var stageClearFinishing = false
    @State private var levelFlashWork: DispatchWorkItem?
    @State private var leakFlashWork: DispatchWorkItem?
    @State private var lastFrameTime: CFTimeInterval = 0
    @State private var stageStartedAt: Date = .distantPast
    private let playFPS: Double = 30
    private let idleFPS: Double = 30
    private let maxSplashKillsPerBlast = 4
    private let minStageSeconds: TimeInterval = 22
    private let maxLives = 5
    private let leakShieldMax = 3
    private let unlockTapTarget = 6
    private let stageClearDuration: CGFloat = 7.5
    private let stageClearSkipAfter: CGFloat = 2.4

    private enum PlayBonus: Equatable {
        case none, doubleScore, rapidFire, slowFruit

        var label: String {
            switch self {
            case .none: return ""
            case .doubleScore: return "2× 分数"
            case .rapidFire: return "火力提升"
            case .slowFruit: return "果潮缓降"
            }
        }
    }

    private struct PendingKill {
        let bubble: GameBubble
        let blast: LaserShot?
    }

    private struct StageClearSnapshot {
        let clearedIndex: Int
        let clearedName: String
        let weaponName: String
        let score: Int
        let maxCombo: Int
        let livesLeft: Int
        let grade: String
        let nextIndex: Int?
        let nextName: String?
        let nextWeapon: String?
        let isFinal: Bool
    }

    private enum Keys {
        static let broken = "disguise.colorPop.brokenTotal"
        static let high = "disguise.colorPop.high"
        static let sound = "disguise.game.soundOn"
        static let careerScore = "disguise.game.careerScore"
        static let maxUnlocked = "disguise.game.maxUnlocked"
        static let saveVersion = "disguise.game.saveVersion"
    }

    /// Unified casual-arcade palette — golden orchard dusk.
    private enum GameTheme {
        static let skyTop = Color(red: 0.35, green: 0.58, blue: 0.95)
        static let skyMid = Color(red: 0.72, green: 0.78, blue: 0.98)
        static let skyWarm = Color(red: 1.0, green: 0.78, blue: 0.52)
        static let skyBottom = Color(red: 1.0, green: 0.90, blue: 0.68)
        static let sunCore = Color(red: 1.0, green: 0.94, blue: 0.62)
        static let horizon = Color(red: 0.38, green: 0.74, blue: 0.42)
        static let ground = Color(red: 0.18, green: 0.46, blue: 0.28)
        static let groundDeep = Color(red: 0.10, green: 0.30, blue: 0.18)
        static let hudGlass = Color.white.opacity(0.18)
        static let hudStroke = Color.white.opacity(0.32)
        static let accent = Color(red: 1.0, green: 0.55, blue: 0.18)
        static let accentDeep = Color(red: 0.90, green: 0.34, blue: 0.14)
        static let beam = Color(red: 0.45, green: 0.98, blue: 0.62)
        static let beamHot = Color(red: 1.0, green: 0.86, blue: 0.35)
        static let shipBody = Color(red: 0.98, green: 0.72, blue: 0.28)
        static let shipWing = Color(red: 0.42, green: 0.78, blue: 0.38)
        static let shipCockpit = Color(red: 0.55, green: 0.88, blue: 0.98)
        static let mist = Color.white.opacity(0.16)
    }

    private func defaultShipY(for size: CGSize = .zero) -> CGFloat {
        let h = size.height > 0 ? size.height : playSize.height
        guard h > 0 else { return 0 }
        let bottomPad = layout.shipBottomPad
        return max(h - bottomPad, h * (layout.compact ? 0.78 : 0.80))
    }

    private func clampShipPosition(x: CGFloat, y: CGFloat) -> (CGFloat, CGFloat) {
        let margin = layout.shipMargin
        let minX = margin
        let maxX = max(minX + 1, playSize.width - margin)
        let minY = playTop + 44 * layout.scale
        let maxY = max(minY + 1, playSize.height - playBottom - 28 * layout.scale)
        return (min(max(x, minX), maxX), min(max(y, minY), maxY))
    }

    private var activeStage: GameProgression.StageDefinition {
        GameProgression.stage(index: playingStage)
    }

    private var stageKillProgress: CGFloat {
        let q = activeStage.killQuota
        guard q > 0 else { return 0 }
        return min(1, CGFloat(killsThisRun) / CGFloat(q))
    }

    private var orchardTheme: GameProgression.OrchardTheme {
        GameProgression.orchardTheme(for: activeStage)
    }

    private var beamProfileNow: GameProgression.BeamProfile {
        GameProgression.beamProfile(for: activeStage)
    }

    private var gameAppVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func persistCareer() {
        UserDefaults.standard.set(careerScore, forKey: Keys.careerScore)
        UserDefaults.standard.set(maxUnlockedStage, forKey: Keys.maxUnlocked)
    }

    private func migrateSaveIfNeeded() {
        let savedVer = UserDefaults.standard.integer(forKey: Keys.saveVersion)
        if savedVer < GameProgression.saveVersion {
            if savedVer < 3 {
                // Preserve progress; clamp to new 99-level cap.
                maxUnlockedStage = GameProgression.clampStage(
                    UserDefaults.standard.integer(forKey: Keys.maxUnlocked)
                )
                playingStage = maxUnlockedStage
            } else {
                maxUnlockedStage = 0
                playingStage = 0
                UserDefaults.standard.set(0, forKey: Keys.maxUnlocked)
            }
            UserDefaults.standard.set(GameProgression.saveVersion, forKey: Keys.saveVersion)
        } else {
            maxUnlockedStage = GameProgression.clampStage(
                UserDefaults.standard.integer(forKey: Keys.maxUnlocked)
            )
        }
    }

    private func bubbleAccent(_ bubble: GameBubble) -> Color {
        bubble.bonusVeg?.accent ?? bubble.fruit.accent
    }

    var body: some View {
        ZStack {
            gameBackdrop.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    ZStack {
                        atmosphereLayer(in: geo.size)
                            .allowsHitTesting(false)

                        orchardSilhouette(in: geo.size)
                            .allowsHitTesting(false)

                        ForEach(stars) { star in
                            Circle()
                                .fill(star.tint.opacity(star.opacity * (skyBreath ? 1.0 : 0.55)))
                                .frame(width: star.size, height: star.size)
                                .position(star.position)
                                .blur(radius: star.size > 3 ? 0.6 : 0)
                                .allowsHitTesting(false)
                        }

                        ForEach(ripples) { ripple in
                            Circle()
                                .stroke(ripple.color.opacity(ripple.opacity), lineWidth: ripple.lineWidth)
                                .frame(width: ripple.size, height: ripple.size)
                                .position(ripple.position)
                                .allowsHitTesting(false)
                        }

                        ForEach(blasts) { blast in
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(blast.opacity * 0.72))
                                    .frame(width: blast.radius * 0.42, height: blast.radius * 0.42)
                                    .blur(radius: 1.5)

                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                blast.color.opacity(blast.opacity * 0.92),
                                                blast.color.opacity(blast.opacity * 0.55),
                                                Color.white.opacity(blast.opacity * 0.22),
                                                Color.clear,
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: blast.radius * 0.78
                                        )
                                    )
                                    .frame(width: blast.radius * 1.65, height: blast.radius * 1.65)

                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(blast.opacity * 0.95),
                                                blast.color.opacity(blast.opacity * 0.75),
                                                blast.color.opacity(blast.opacity * 0.15),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: blast.ringWidth
                                    )
                                    .frame(width: blast.radius * 2.15, height: blast.radius * 2.15)

                                if blast.tier >= 1 {
                                    Circle()
                                        .stroke(blast.color.opacity(blast.opacity * 0.42), lineWidth: max(1, blast.ringWidth * 0.55))
                                        .frame(width: blast.radius * 1.45, height: blast.radius * 1.45)
                                }

                                if blast.tier >= 2 {
                                    ForEach(0..<2, id: \.self) { i in
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(blast.opacity * 0.7), Color.clear],
                                                    startPoint: .center,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(1.5, blast.ringWidth * 0.45), height: blast.radius * 0.95)
                                            .rotationEffect(.degrees(Double(i) * 90 + blast.sparkAngle))
                                    }
                                }
                            }
                            .position(blast.position)
                            .allowsHitTesting(false)
                        }

                        ForEach(shards) { shard in
                            Group {
                                if shard.isDrop {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [Color.white.opacity(0.55), shard.color, shard.color.opacity(0.55)],
                                                center: UnitPoint(x: 0.32, y: 0.28),
                                                startRadius: 0,
                                                endRadius: shard.width
                                            )
                                        )
                                        .frame(width: shard.width, height: shard.width)
                                } else if shard.isSpark {
                                    Circle()
                                        .fill(Color.white.opacity(shard.opacity))
                                        .frame(width: shard.width, height: shard.width)
                                        .blur(radius: shard.blur)
                                } else {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.45), shard.color, shard.color.opacity(0.65)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: shard.width, height: shard.height)
                                }
                            }
                            .rotationEffect(.degrees(shard.rotation))
                            .opacity(shard.opacity)
                            .position(shard.position)
                            .allowsHitTesting(false)
                        }

                        ForEach(bubbles) { bubble in
                            fruitView(bubble, lite: isPlaying)
                                .position(bubble.position)
                                .zIndex(Double(bubble.size))
                                .allowsHitTesting(false)
                        }

                        ForEach(shots) { shot in
                            laserBolt(shot)
                                .position(x: shot.position.x, y: shot.position.y)
                                .allowsHitTesting(false)
                        }

                        ForEach(floatTexts) { ft in
                            Text(ft.text)
                                .font(.system(size: ft.fontSize, weight: .black, design: .rounded))
                                .foregroundStyle(ft.color)
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                                .opacity(ft.opacity)
                                .position(ft.position)
                                .allowsHitTesting(false)
                        }

                        if shipReady {
                            launcherView
                                .position(x: shipX, y: shipY)
                                .allowsHitTesting(false)
                        }

                        if levelFlash {
                            GameTheme.beamHot.opacity(0.18).ignoresSafeArea().allowsHitTesting(false)
                        }
                    }

                    if isPlaying, shipReady, !stageCelebrating {
                        Color.clear
                            .frame(width: playSize.width, height: playSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let (x, y) = clampShipPosition(x: value.location.x, y: value.location.y)
                                        shipX = x
                                        shipY = y
                                    }
                            )
                    } else if playSize.height > playTop + playBottom + 40 {
                        let bandH = playSize.height - playTop - playBottom
                        Color.clear
                            .frame(width: playSize.width, height: bandH)
                            .contentShape(Rectangle())
                            .position(x: playSize.width * 0.5, y: playTop + bandH * 0.5)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard shipReady else { return }
                                        let (x, _) = clampShipPosition(x: value.location.x, y: defaultShipY())
                                        shipX = x
                                    }
                            )
                    }
                }
                .onAppear {
                    updatePlayfield(geo.size)
                    if !shipReady {
                        shipX = geo.size.width * 0.5
                        shipY = defaultShipY(for: geo.size)
                        shipReady = true
                    }
                    if stars.isEmpty { seedStars(in: geo.size) }
                    if bubbles.isEmpty { seedIdleBubbles() }
                    startMotionLoop()
                }
                .onChange(of: geo.size) { newSize in
                    updatePlayfield(newSize)
                    if stars.count < 12 { seedStars(in: newSize) }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if isPlaying {
                        playTopHUD
                    } else {
                        topHUD
                    }
                }
                .padding(.horizontal, layout.hudHorizontalPadding)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if !isPlaying {
                    VStack(spacing: 12) {
                        homeCard
                            .onTapGesture { handleUnlockTap() }
                        bottomBar
                    }
                    .padding(.bottom, layout.homeBottomPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    HStack {
                        Spacer()
                        subtleStopButton
                    }
                    .padding(.trailing, layout.hudHorizontalPadding)
                    .padding(.bottom, layout.stopButtonBottom)
                    .opacity(stageCelebrating ? 0 : 1)
                    .allowsHitTesting(!stageCelebrating)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isPlaying)
            .onChange(of: isPlaying) { _ in
                if playSize.width > 0 { updatePlayfield(playSize) }
            }
            .ignoresSafeArea(edges: .top)
            .zIndex(20)

            if leakFlash {
                Color.red.opacity(0.28)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if stageCelebrating, let snap = stageClearSnapshot {
                stageClearOverlay(snap)
                    .zIndex(30)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onDisappear {
            stopGame()
            motionTask?.cancel()
            motionTask = nil
            fireTask?.cancel()
            unlockTapResetTask?.cancel()
            stageClearTask?.cancel()
            cancelPendingEffectWork()
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            migrateSaveIfNeeded()
            playingStage = maxUnlockedStage
            GameHaptics.prepare()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                startPulse = true
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                skyBreath = true
                sunPulse = true
            }
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                cloudDrift = 1
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                petalSpin = 360
            }
        }
        .onChange(of: soundOn) { on in
            UserDefaults.standard.set(on, forKey: Keys.sound)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                pausedByBackground = isPlaying
                shards.removeAll()
                ripples.removeAll()
                blasts.removeAll()
                floatTexts.removeAll()
                shots.removeAll()
                motionTask?.cancel()
                motionTask = nil
                spawnTask?.cancel()
                spawnTask = nil
                fireTask?.cancel()
                fireTask = nil
                // Pause clear countdown — do not auto-advance in background.
                stageClearTask?.cancel()
                stageClearTask = nil
            } else {
                startMotionLoop()
                if stageCelebrating, stageClearSnapshot != nil {
                    beginStageClearCountdown(
                        cleared: stageClearSnapshot!.clearedIndex,
                        isFinal: stageClearSnapshot!.isFinal,
                        fromProgress: stageClearProgress
                    )
                } else if pausedByBackground, isPlaying {
                    resumePlayingLoops()
                }
                pausedByBackground = false
            }
        }
    }

    private func updatePlayfield(_ size: CGSize) {
        playSize = size
        let insets = keyWindowSafeInsets()
        layout = GameLayoutMetrics.resolve(size: size, safeInsets: insets)
        playTop = layout.playTop(isPlaying: isPlaying)
        playBottom = layout.playBottom(isPlaying: isPlaying)
        let margin = layout.shipMargin
        if !shipReady {
            shipX = size.width * 0.5
            shipY = defaultShipY(for: size)
            shipReady = true
        } else {
            shipX = min(max(shipX, margin), max(margin, size.width - margin))
            if !isPlaying {
                shipY = defaultShipY(for: size)
            } else {
                let clamped = clampShipPosition(x: shipX, y: shipY)
                shipX = clamped.0
                shipY = clamped.1
            }
        }
    }

    private func keyWindowSafeInsets() -> UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    // MARK: - Visuals

    private var gameBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    orchardTheme.skyTop,
                    orchardTheme.skyMid,
                    orchardTheme.skyWarm,
                    orchardTheme.skyBottom,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Sun glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            orchardTheme.sunCore.opacity(sunPulse ? 0.98 : 0.75),
                            orchardTheme.skyWarm.opacity(0.42),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: sunPulse ? 175 : 140
                    )
                )
                .frame(width: layout.tall ? 340 : 300, height: layout.tall ? 340 : 300)
                .offset(x: layout.wide ? 128 : 118, y: layout.sunOffsetY)
                .blur(radius: 2)

            // Distant atmospheric band
            LinearGradient(
                colors: [
                    Color.clear,
                    orchardTheme.skyMid.opacity(0.18),
                    orchardTheme.horizon.opacity(0.12),
                    Color.clear,
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: UnitPoint(x: 0.5, y: 0.72)
            )

            // Secondary warm fill near horizon
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orchardTheme.skyWarm.opacity(0.45), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 220)
                .offset(y: 40)
                .blur(radius: 20)

            RadialGradient(
                colors: [Color.white.opacity(skyBreath ? 0.32 : 0.16), Color.clear],
                center: UnitPoint(x: 0.78, y: 0.10),
                startRadius: 8,
                endRadius: 240
            )

            RadialGradient(
                colors: [orchardTheme.horizon.opacity(0.22), Color.clear],
                center: UnitPoint(x: 0.18, y: 0.78),
                startRadius: 12,
                endRadius: 300
            )

            // Horizon wash
            LinearGradient(
                colors: [
                    Color.clear,
                    orchardTheme.horizon.opacity(0.28),
                    orchardTheme.ground.opacity(0.48),
                    orchardTheme.groundDeep.opacity(0.72),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.55),
                endPoint: .bottom
            )

            // Soft vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.18)],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
            .blendMode(.multiply)
            .opacity(0.55)
        }
    }

    private func atmosphereLayer(in size: CGSize) -> some View {
        let drift = cloudDrift * size.width * 0.35
        return ZStack {
            // Soft clouds
            cloudBlob(width: size.width * 0.42, height: 36)
                .position(x: size.width * 0.22 + drift * 0.4, y: size.height * 0.14)
                .opacity(0.55)
            cloudBlob(width: size.width * 0.55, height: 44)
                .position(x: size.width * 0.72 - drift * 0.25, y: size.height * 0.20)
                .opacity(0.42)
            cloudBlob(width: size.width * 0.36, height: 28)
                .position(x: size.width * 0.48 + drift * 0.18, y: size.height * 0.28)
                .opacity(0.32)

            // Floating petals / pollen
            ForEach(0..<8, id: \.self) { i in
                let baseX = size.width * (0.08 + Double(i) * 0.11)
                let baseY = size.height * (0.18 + Double(i % 4) * 0.12)
                Circle()
                    .fill(i % 2 == 0 ? GameTheme.accent.opacity(0.55) : Color.white.opacity(0.55))
                    .frame(width: i % 3 == 0 ? 5 : 3.5, height: i % 3 == 0 ? 5 : 3.5)
                    .blur(radius: 0.4)
                    .offset(
                        x: cos((petalSpin + Double(i) * 40) * .pi / 180) * 18,
                        y: sin((petalSpin + Double(i) * 55) * .pi / 180) * 22
                    )
                    .position(x: baseX, y: baseY)
                    .opacity(skyBreath ? 0.9 : 0.4)
            }

            // Floating leaves
            ForEach(0..<6, id: \.self) { i in
                let drift = sin((petalSpin + Double(i) * 48) * .pi / 180)
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [orchardTheme.horizon.opacity(0.75), orchardTheme.ground.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 10 + CGFloat(i % 3) * 2, height: 6 + CGFloat(i % 2) * 2)
                    .rotationEffect(.degrees(18 + Double(i) * 22 + drift * 12))
                    .position(
                        x: size.width * (0.12 + Double(i) * 0.14) + drift * 24,
                        y: size.height * (0.22 + Double(i % 3) * 0.11)
                    )
                    .opacity(skyBreath ? 0.72 : 0.38)
            }

            // Light shafts
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 36 + CGFloat(i) * 10, height: size.height * 0.55)
                    .rotationEffect(.degrees(-18 + Double(i) * 10))
                    .position(
                        x: size.width * (0.55 + Double(i) * 0.12),
                        y: size.height * 0.32
                    )
                    .opacity(skyBreath ? 0.55 : 0.25)
                    .blur(radius: 6)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func cloudBlob(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: -width * 0.12) {
            Capsule().fill(orchardTheme.mist).frame(width: width * 0.55, height: height * 0.7)
            Capsule().fill(Color.white.opacity(0.18)).frame(width: width * 0.7, height: height)
            Capsule().fill(orchardTheme.mist).frame(width: width * 0.45, height: height * 0.6)
        }
        .blur(radius: 8)
    }

    private func orchardSilhouette(in size: CGSize) -> some View {
        let groundY = size.height * 0.90
        return ZStack {
            // Distant tree line
            HStack(alignment: .bottom, spacing: size.width * 0.04) {
                distantTree(height: 72, width: 48, opacity: 0.28)
                distantTree(height: 96, width: 58, opacity: 0.34)
                distantTree(height: 64, width: 44, opacity: 0.24)
                distantTree(height: 88, width: 54, opacity: 0.30)
                distantTree(height: 70, width: 46, opacity: 0.26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 6)
            .padding(.bottom, max(36, size.height * 0.12))
            .offset(x: cloudDrift * size.width * 0.04)

            // Layered hills
            Ellipse()
                .fill(orchardTheme.groundDeep.opacity(0.55))
                .frame(width: size.width * 1.4, height: size.height * 0.28)
                .position(x: size.width * 0.35, y: groundY + 8)
            Ellipse()
                .fill(orchardTheme.ground.opacity(0.42))
                .frame(width: size.width * 1.25, height: size.height * 0.22)
                .position(x: size.width * 0.7, y: groundY)

            // Soft fog line
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: size.width * 1.1, height: 18)
                .blur(radius: 10)
                .position(x: size.width * 0.5, y: groundY - size.height * 0.06)

            HStack(alignment: .bottom, spacing: size.width * 0.05) {
                bush(height: 58, width: 76)
                bush(height: 40, width: 58)
                bush(height: 68, width: 90)
                bush(height: 46, width: 64)
                bush(height: 54, width: 70)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 10)
            .padding(.bottom, max(10, size.height * 0.05))
            .opacity(0.55)
        }
        .frame(width: size.width, height: size.height)
    }

    private func bush(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(orchardTheme.groundDeep.opacity(0.9))
                .frame(width: width * 0.16, height: height * 0.4)
            Circle()
                .fill(orchardTheme.horizon.opacity(0.88))
                .frame(width: width * 0.42, height: width * 0.42)
                .offset(x: -width * 0.18, y: -height * 0.18)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [orchardTheme.horizon, orchardTheme.ground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width * 0.52, height: width * 0.52)
                .offset(y: -height * 0.26)
            Circle()
                .fill(orchardTheme.horizon.opacity(0.82))
                .frame(width: width * 0.38, height: width * 0.38)
                .offset(x: width * 0.2, y: -height * 0.14)
            // Fruit dots on bush
            Circle()
                .fill(GameTheme.accent.opacity(0.85))
                .frame(width: 5, height: 5)
                .offset(x: -width * 0.06, y: -height * 0.42)
            Circle()
                .fill(GameTheme.beamHot.opacity(0.8))
                .frame(width: 4, height: 4)
                .offset(x: width * 0.12, y: -height * 0.36)
        }
        .frame(width: width, height: height, alignment: .bottom)
        .shadow(color: orchardTheme.groundDeep.opacity(0.35), radius: 6, y: 3)
    }

    private func distantTree(height: CGFloat, width: CGFloat, opacity: Double) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(orchardTheme.groundDeep.opacity(0.85))
                .frame(width: width * 0.12, height: height * 0.42)
            Ellipse()
                .fill(orchardTheme.ground.opacity(opacity))
                .frame(width: width * 0.95, height: width * 0.72)
                .offset(y: -height * 0.34)
            Ellipse()
                .fill(orchardTheme.horizon.opacity(opacity * 0.9))
                .frame(width: width * 0.72, height: width * 0.52)
                .offset(x: -width * 0.12, y: -height * 0.28)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    @ViewBuilder
    private func fruitView(_ bubble: GameBubble, lite: Bool = false) -> some View {
        if lite {
            fruitViewLite(bubble)
        } else {
            fruitViewFull(bubble)
        }
    }

    private func fruitViewLite(_ bubble: GameBubble) -> some View {
        let iconSize = bubble.size * 0.72
        let accent = bubbleAccent(bubble)
        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: bubble.size * 1.08, height: bubble.size * 1.08)
            Circle()
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.2)
                .frame(width: bubble.size * 1.04, height: bubble.size * 1.04)
            ProduceIconView(fruit: bubble.fruit, vegetable: bubble.bonusVeg, size: iconSize)
            if bubble.maxHp > 1 {
                Circle()
                    .trim(from: 0, to: CGFloat(bubble.hp) / CGFloat(max(1, bubble.maxHp)))
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: bubble.size * 1.14, height: bubble.size * 1.14)
                    .rotationEffect(.degrees(-90))
            }
            if bubble.bonusVeg != nil {
                Circle()
                    .strokeBorder(Color(red: 0.45, green: 0.92, blue: 0.52).opacity(0.9), lineWidth: 1.8)
                    .frame(width: bubble.size * 1.16, height: bubble.size * 1.16)
            } else if bubble.isGolden {
                Circle()
                    .strokeBorder(GameTheme.beamHot.opacity(0.75), lineWidth: 1.8)
                    .frame(width: bubble.size * 1.16, height: bubble.size * 1.16)
            }
        }
        .frame(width: bubble.size * 1.22, height: bubble.size * 1.22)
        .scaleEffect(bubble.scale)
    }

    private func fruitViewFull(_ bubble: GameBubble) -> some View {
        let hpRatio = CGFloat(bubble.hp) / CGFloat(max(1, bubble.maxHp))
        let iconSize = bubble.size * (bubble.kind == .titan ? 0.68 : 0.76)
        let accent = bubbleAccent(bubble)
        return ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: bubble.size * 1.28, height: bubble.size * 1.28)
                .blur(radius: 5)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: bubble.size * 1.1, height: bubble.size * 1.1)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), accent.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                )

            ProduceIconView(fruit: bubble.fruit, vegetable: bubble.bonusVeg, size: iconSize)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1.5)

            if bubble.maxHp > 1 {
                Circle()
                    .trim(from: 0, to: hpRatio)
                    .stroke(
                        AngularGradient(
                            colors: [Color.white, accent, Color.white.opacity(0.85)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                    )
                    .frame(width: bubble.size * 1.2, height: bubble.size * 1.2)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.35), radius: 3)
            }

            if bubble.kind == .titan {
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 2.4)
                    .frame(width: bubble.size * 1.26, height: bubble.size * 1.26)
                Circle()
                    .strokeBorder(GameTheme.beamHot.opacity(0.5), lineWidth: 1.2)
                    .frame(width: bubble.size * 1.36, height: bubble.size * 1.36)
            }

            if bubble.bonusVeg != nil {
                Circle()
                    .strokeBorder(Color(red: 0.45, green: 0.92, blue: 0.52).opacity(0.85), lineWidth: 2.2)
                    .frame(width: bubble.size * 1.22, height: bubble.size * 1.22)
            } else if bubble.isGolden {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [GameTheme.beamHot, .white, GameTheme.beam, GameTheme.beamHot],
                            center: .center
                        ),
                        lineWidth: 2.2
                    )
                    .frame(width: bubble.size * 1.3, height: bubble.size * 1.3)
                    .rotationEffect(.degrees(petalSpin * 0.4))
                Text("✨")
                    .font(.system(size: bubble.size * 0.22))
                    .offset(y: -bubble.size * 0.62)
            }
        }
        .frame(width: bubble.size * 1.38, height: bubble.size * 1.38)
        .scaleEffect(bubble.scale)
        .shadow(color: accent.opacity(0.28), radius: 8, y: 4)
    }

    private func laserBolt(_ shot: LaserShot) -> some View {
        Group {
            switch shot.style {
            case .rail: railBolt(shot)
            case .plasma, .nova: plasmaBolt(shot)
            case .missile: missileBolt(shot)
            case .prism: prismBolt(shot)
            case .twin, .spread, .pulse: pulseBolt(shot)
            }
        }
    }

    private func pulseBolt(_ shot: LaserShot) -> some View {
        ZStack {
            Capsule()
                .fill(shot.glow.opacity(0.25))
                .frame(width: shot.width * 2.8 * shot.trailScale, height: shot.length * 1.1)
                .blur(radius: 3)
            Capsule()
                .fill(shot.gradient)
                .frame(width: shot.width, height: shot.length)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8))
            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: max(1.2, shot.width * 0.28), height: shot.length * 0.82)
            Circle()
                .fill(Color.white)
                .frame(width: shot.width * 1.1, height: shot.width * 1.1)
                .shadow(color: shot.glow, radius: 4)
                .offset(y: -shot.length * 0.48)
        }
    }

    private func railBolt(_ shot: LaserShot) -> some View {
        ZStack {
            Capsule()
                .fill(shot.glow.opacity(0.35))
                .frame(width: shot.width * 3.2, height: shot.length * 1.05)
                .blur(radius: 4)
            Rectangle()
                .fill(shot.gradient)
                .frame(width: shot.width * 0.55, height: shot.length)
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.85), lineWidth: 0.6))
            Rectangle()
                .fill(Color.white)
                .frame(width: shot.width * 0.18, height: shot.length * 0.92)
        }
    }

    private func plasmaBolt(_ shot: LaserShot) -> some View {
        ZStack {
            Circle()
                .fill(shot.glow.opacity(0.22))
                .frame(width: shot.width * 4.5, height: shot.width * 4.5)
                .offset(y: -shot.length * 0.35)
            Capsule()
                .fill(shot.gradient)
                .frame(width: shot.width * 0.75, height: shot.length * 0.72)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, shot.glow, shot.glow.opacity(0.2)],
                        center: .center,
                        startRadius: 0,
                        endRadius: shot.width * 0.9
                    )
                )
                .frame(width: shot.width * 1.6, height: shot.width * 1.6)
                .offset(y: -shot.length * 0.42)
                .shadow(color: shot.glow, radius: 6)
        }
    }

    private func missileBolt(_ shot: LaserShot) -> some View {
        ZStack {
            Capsule()
                .fill(shot.glow.opacity(0.2))
                .frame(width: shot.width * 1.6, height: shot.length * 0.85)
                .blur(radius: 2)
            RoundedRectangle(cornerRadius: shot.width * 0.35, style: .continuous)
                .fill(shot.gradient)
                .frame(width: shot.width * 0.9, height: shot.length * 0.55)
            Triangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: shot.width * 0.7, height: shot.width * 0.55)
                .offset(y: -shot.length * 0.32)
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: shot.width * 0.35, height: shot.width * 0.35)
                .offset(y: shot.length * 0.18)
                .blur(radius: 1)
        }
    }

    private func prismBolt(_ shot: LaserShot) -> some View {
        ZStack {
            Diamond()
                .fill(shot.gradient)
                .frame(width: shot.width * 1.4, height: shot.length * 0.55)
            Diamond()
                .stroke(Color.white.opacity(0.75), lineWidth: 0.8)
                .frame(width: shot.width * 1.4, height: shot.length * 0.55)
            Capsule()
                .fill(shot.glow.opacity(0.35))
                .frame(width: shot.width * 0.35, height: shot.length * 0.65)
        }
    }

    private var launcherView: some View {
        let profile = beamProfileNow
        let accent = profile.glow
        let hull = Color(red: 0.14, green: 0.18, blue: 0.28)
        let hullLight = Color(red: 0.28, green: 0.36, blue: 0.52)
        let scale: CGFloat = layout.scale * (1.0 + CGFloat(playingStage) * 0.012)
        let pulse = 0.65 + sin(thrustPhase) * 0.25
        let barrelCount = max(1, profile.volley.count)

        return ZStack {
            Ellipse()
                .fill(accent.opacity(0.12))
                .frame(width: 72, height: 14)
                .offset(y: 36)
                .blur(radius: 4)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.55 * pulse), accent.opacity(0.05), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 14, height: 22 + sin(thrustPhase * 1.6) * 6)
                .offset(y: 28)

            HStack(spacing: 46) {
                wingPanel(color: hullLight, accent: accent)
                wingPanel(color: hullLight, accent: accent)
            }

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [hullLight, hull, Color(red: 0.08, green: 0.10, blue: 0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 52, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), accent.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), accent, accent.opacity(0.35)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 14
                    )
                )
                .frame(width: 22, height: 22)
                .shadow(color: accent.opacity(pulse), radius: 8)
                .offset(y: -2)

            HStack(spacing: barrelCount > 2 ? 8 : 14) {
                ForEach(0..<min(barrelCount, 4), id: \.self) { _ in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), accent, hull],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 5, height: 22 + CGFloat(playingStage) * 0.15)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                }
            }
            .offset(y: -22)

            Text(profile.style.displayName)
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .offset(y: 14)
        }
        .frame(width: 88, height: 88)
        .scaleEffect(scale)
        .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
    }

    private func wingPanel(color: Color, accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 18, height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 0.6)
            )
            .rotationEffect(.degrees(-18))
    }

    private func hudFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .rounded) -> Font {
        .system(size: size * layout.hudFontScale, weight: weight, design: design)
    }

    private var topHUD: some View {
        let stage = GameProgression.stage(index: maxUnlockedStage)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [GameTheme.accent, GameTheme.accentDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .shadow(color: GameTheme.accentDeep.opacity(0.35), radius: 4, y: 2)
                    Text("🍎")
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("水果保卫战")
                        .font(hudFont(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    Text("第 \(maxUnlockedStage + 1) 关 · \(stage.name)")
                        .font(hudFont(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.32), radius: 2, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    hudCircleButton(icon: "square.and.arrow.up", action: presentShare)
                    hudCircleButton(icon: "gearshape.fill") { showSettings = true }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    idleStatChip(icon: "star.fill", text: "\(score)", tint: GameTheme.accentDeep)
                    idleStatChip(icon: "flag.fill", text: "Lv.\(maxUnlockedStage + 1)", tint: beamProfileNow.glow)
                    idleStatChip(icon: "bolt.fill", text: stage.weapon.displayName, tint: GameTheme.beam)
                    idleStatChip(icon: "target", text: "\(stage.killQuota) 击", tint: GameTheme.accent)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 14)
        .padding(.top, layout.safeTop + 4)
    }

    /// Playing HUD — two rows so stats are not clipped on narrow screens.
    private var playTopHUD: some View {
        let stage = activeStage
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    playStatPill(icon: "star.fill", text: "\(score)", tint: GameTheme.accentDeep)
                    playStatPill(icon: "flag.fill", text: "Lv.\(playingStage + 1)", tint: beamProfileNow.glow)
                    playStatPill(icon: "target", text: "\(killsThisRun)/\(stage.killQuota)", tint: GameTheme.accent)
                }
                HStack(spacing: 5) {
                    playLivesPill
                    if combo > 1 {
                        playStatPill(icon: "flame.fill", text: "×\(combo)", tint: GameTheme.accent)
                    }
                    if activeBonus != .none, bonusTimer > 0 {
                        playStatPill(icon: "sparkles", text: activeBonus.label, tint: GameTheme.beamHot)
                    }
                }
            }
            Spacer(minLength: 4)
            playSettingsButton
        }
        .padding(.horizontal, 12)
        .padding(.top, layout.safeTop + 4)
    }

    private func hudCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6))
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func idleStatChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(hudFont(size: 10, weight: .heavy).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.2))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
        )
    }

    private func playStatPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(hudFont(size: 10, weight: .heavy).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.22))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        )
    }

    private var playSettingsButton: some View {
        settingsButton(compact: true)
    }

    private func settingsButton(compact: Bool) -> some View {
        Button {
            showSettings = true
        } label: {
            Group {
                if compact {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("设置")
                            .font(hudFont(size: 11, weight: .heavy))
                    }
                }
            }
            .foregroundStyle(compact ? .white : Color(red: 0.28, green: 0.20, blue: 0.14))
            .shadow(color: compact ? .black.opacity(0.4) : .clear, radius: 2, y: 1)
            .padding(.horizontal, compact ? 0 : 10)
            .padding(.vertical, compact ? 0 : 7)
            .frame(width: compact ? 28 : nil, height: compact ? 28 : nil)
            .background {
                if compact {
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6))
                } else {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.72), GameTheme.beam.opacity(0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(GameTheme.beam.opacity(0.42), lineWidth: 0.9)
                        )
                        .shadow(color: GameTheme.beam.opacity(0.18), radius: 6, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("设置")
    }

    private var playLivesPill: some View {
        HStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<maxLives, id: \.self) { i in
                    Image(systemName: i < lives ? "heart.fill" : "heart")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(i < lives ? Color(red: 0.98, green: 0.35, blue: 0.42) : .white.opacity(0.35))
                }
            }
            HStack(spacing: 1) {
                ForEach(0..<leakShieldMax, id: \.self) { i in
                    Circle()
                        .fill(i < leakShield ? Color(red: 0.45, green: 0.92, blue: 1.0) : Color.white.opacity(0.22))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        )
        .accessibilityLabel("生命 \(lives)，护盾 \(leakShield)")
    }

    private var homeCard: some View {
        let stage = GameProgression.stage(index: maxUnlockedStage)
        return VStack(spacing: 4) {
            Text("第 \(maxUnlockedStage + 1) 关 · \(stage.name)")
                .font(hudFont(size: 15, weight: .heavy))
                .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.14))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(stage.weapon.displayName) · 目标 \(stage.killQuota) 击")
                .font(hudFont(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                )
        )
    }

    private var bottomBar: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                startGame()
            }
            if playSize.width > 0 { updatePlayfield(playSize) }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(GameTheme.accent.opacity(startPulse ? 0.28 : 0.14))
                    .scaleEffect(startPulse ? 1.08 : 1.0)
                    .allowsHitTesting(false)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GameTheme.accent, GameTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    )
                    .shadow(color: GameTheme.accentDeep.opacity(0.38), radius: 10, y: 4)

                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("开始游戏")
                        .font(hudFont(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: layout.startButtonSize.width, height: layout.startButtonSize.height)
            .compositingGroup()
        }
        .buttonStyle(.plain)
    }

    /// Corner stop control — readable over busy playfield without covering the ship.
    private var subtleStopButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                stopGame()
                seedIdleBubbles()
            }
            if playSize.width > 0 { updatePlayfield(playSize) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text("暂停")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.55),
                                Color(red: 0.12, green: 0.14, blue: 0.22).opacity(0.72),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.cyan.opacity(0.35),
                                Color.white.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("暂停并结束本局")
    }

    private func stageGrade(lives: Int, maxCombo: Int) -> String {
        if lives >= maxLives && maxCombo >= 12 { return "S" }
        if lives >= maxLives - 1 && maxCombo >= 8 { return "A" }
        if lives >= 2 { return "B" }
        return "C"
    }

    @ViewBuilder
    private func stageClearOverlay(_ snap: StageClearSnapshot) -> some View {
        let festiveRed = Color(red: 0.88, green: 0.24, blue: 0.20)
        let festiveGold = Color(red: 1.0, green: 0.84, blue: 0.42)
        let festiveOrange = Color(red: 1.0, green: 0.56, blue: 0.16)
        let cardTop = Color(red: 0.22, green: 0.10, blue: 0.14)
        let cardBottom = Color(red: 0.12, green: 0.07, blue: 0.11)
        let canContinue = stageClearProgress >= stageClearSkipAfter / stageClearDuration
        let cardReveal = min(1, max(0, (stageClearProgress - 0.12) / 0.88))
        let cheerLine: String = {
            switch snap.grade {
            case "S": return "太棒了！完美守护果园 🎉"
            case "A": return "精彩一战！你越来越强了 ✨"
            case "B": return "稳扎稳打，这一关拿下来了 💪"
            default: return "辛苦了！每一关都是进步 🍊"
            }
        }()

        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    festiveGold.opacity(0.22),
                    festiveOrange.opacity(0.10),
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 18) {
                if stageClearProgress < 0.28 {
                    Text("✨ 关卡完成！")
                        .font(hudFont(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                // Ribbon header
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(festiveGold)
                    Text(snap.isFinal ? "全关卡通关" : "关卡通过")
                        .font(hudFont(size: 15, weight: .heavy))
                        .tracking(0.6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(festiveGold)
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [festiveGold, Color.white.opacity(0.95), festiveGold],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(festiveRed.opacity(0.55))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(festiveGold.opacity(0.55), lineWidth: 1)
                        )
                )

                Text(cheerLine)
                    .font(hudFont(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)

                // Grade medal
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [festiveGold.opacity(0.35), festiveOrange.opacity(0.18), Color.clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 56
                            )
                        )
                        .frame(width: 112, height: 112)
                        .blur(radius: 2)

                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [festiveGold, .white, festiveOrange, festiveRed.opacity(0.8), festiveGold],
                                center: .center
                            ),
                            lineWidth: 3.5
                        )
                        .frame(width: 96, height: 96)
                        .shadow(color: festiveGold.opacity(0.55), radius: 12, y: 2)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.32, green: 0.14, blue: 0.16),
                                    Color(red: 0.18, green: 0.08, blue: 0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 82, height: 82)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        )

                    Text(snap.grade)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [festiveGold, .white, festiveOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: festiveRed.opacity(0.45), radius: 4, y: 2)
                }

                VStack(spacing: 6) {
                    Text("第 \(snap.clearedIndex + 1) 关 · \(snap.clearedName)")
                        .font(hudFont(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(festiveGold)
                        Text(snap.weaponName)
                            .font(hudFont(size: 12, weight: .semibold))
                            .foregroundStyle(festiveGold.opacity(0.95))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule(style: .continuous).strokeBorder(festiveGold.opacity(0.28), lineWidth: 0.7))
                    )
                }

                HStack(spacing: 10) {
                    clearStatChip(icon: "star.fill", title: "本关", value: "\(snap.score)", tint: festiveGold)
                    clearStatChip(icon: "flame.fill", title: "连击", value: "×\(snap.maxCombo)", tint: festiveOrange)
                    clearStatChip(icon: "heart.fill", title: "生命", value: "\(snap.livesLeft)", tint: festiveRed)
                }

                if let next = snap.nextIndex, let nextName = snap.nextName {
                    VStack(spacing: 8) {
                        Label("下一关等你挑战", systemImage: "flag.checkered")
                            .font(hudFont(size: 11, weight: .bold))
                            .foregroundStyle(festiveGold)

                        VStack(spacing: 5) {
                            Text("第 \(next + 1) 关 · \(nextName)")
                                .font(hudFont(size: 16, weight: .heavy))
                                .foregroundStyle(.white)
                            if let weapon = snap.nextWeapon {
                                Label("新武器 · \(weapon)", systemImage: "scope")
                                    .font(hudFont(size: 11, weight: .semibold))
                                    .foregroundStyle(GameTheme.beam.opacity(0.95))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            festiveGold.opacity(0.22),
                                            festiveOrange.opacity(0.14),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(festiveGold.opacity(0.45), lineWidth: 1)
                                )
                        )
                    }
                } else if snap.isFinal {
                    VStack(spacing: 6) {
                        Text("🏆")
                            .font(.system(size: 28))
                        Text("百果神域已征服")
                            .font(hudFont(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("你是传奇果园守护者")
                            .font(hudFont(size: 11, weight: .semibold))
                            .foregroundStyle(festiveGold.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(festiveGold.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(festiveGold.opacity(0.42), lineWidth: 1)
                            )
                    )
                }

                VStack(spacing: 10) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [festiveOrange, festiveGold, festiveRed.opacity(0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, g.size.width * stageClearProgress))
                                .shadow(color: festiveGold.opacity(0.55), radius: 4, y: 0)
                        }
                    }
                    .frame(height: 7)

                    if canContinue {
                        Button {
                            skipStageClearTransition()
                        } label: {
                            HStack(spacing: 8) {
                                Text(snap.isFinal ? "太棒了" : "继续闯关")
                                    .font(hudFont(size: 16, weight: .heavy))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [festiveOrange, festiveRed],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(festiveGold.opacity(0.65), lineWidth: 1.2)
                                    )
                                    .shadow(color: festiveRed.opacity(0.5), radius: 14, y: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(festiveGold)
                                .scaleEffect(0.8)
                            Text("结算中，稍安勿躁…")
                                .font(hudFont(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [cardTop, cardBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.regularMaterial.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        festiveGold.opacity(0.85),
                                        Color.white.opacity(0.45),
                                        festiveOrange.opacity(0.55),
                                        festiveGold.opacity(0.35),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(height: 72)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: festiveRed.opacity(0.35), radius: 32, y: 14)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            }
            .padding(.horizontal, 22)
            .scaleEffect(0.94 + cardReveal * 0.06)
            .opacity(cardReveal)
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: stageClearProgress)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: canContinue)
    }

    private func clearStatChip(icon: String, title: String, value: String, tint: Color = GameTheme.beamHot) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                        .overlay(Circle().strokeBorder(tint.opacity(0.32), lineWidth: 0.7))
                )
            Text(title)
                .font(hudFont(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(value)
                .font(hudFont(size: 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
        )
    }

    private var settingsSheet: some View {
        let stage = GameProgression.stage(index: maxUnlockedStage)
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    settingsShareHero(stage: stage)

                    settingsCard(title: "战绩档案", icon: "chart.bar.fill", tint: GameTheme.accent) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            settingsMiniStat(icon: "flag.fill", label: "当前关卡", value: "第 \(maxUnlockedStage + 1) 关", tint: GameTheme.accentDeep)
                            settingsMiniStat(icon: "bolt.fill", label: "武器", value: stage.weapon.displayName, tint: GameTheme.beam)
                            settingsMiniStat(icon: "target", label: "通关目标", value: "\(stage.killQuota) 击", tint: GameTheme.accent)
                            settingsMiniStat(icon: "heart.fill", label: "生命", value: "\(lives)/\(maxLives)", tint: Color(red: 0.98, green: 0.35, blue: 0.42))
                            settingsMiniStat(icon: "star.fill", label: "本局分数", value: "\(score)", tint: GameTheme.beamHot)
                            settingsMiniStat(icon: "trophy.fill", label: "历史最高", value: "\(highScore)", tint: GameTheme.accentDeep)
                            settingsMiniStat(icon: "sum", label: "累计分数", value: "\(careerScore)", tint: GameTheme.beam)
                            settingsMiniStat(icon: "sparkles", label: "累计击破", value: "\(brokenTotal)", tint: GameTheme.accent)
                        }
                        Text("「\(stage.name)」· 共 \(GameProgression.maxStageIndex + 1) 关 orchard 征程")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }

                    settingsCard(title: "手感", icon: "hand.tap.fill", tint: GameTheme.beam) {
                        settingsToggleRow(icon: "speaker.wave.2.fill", title: "游戏音效", subtitle: "射击、爆破与过关音效", isOn: $soundOn, tint: GameTheme.accent)
                        Divider().opacity(0.35)
                        settingsToggleRow(icon: "iphone.radiowaves.left.and.right", title: "破碎震感", subtitle: "击中与过关触觉反馈", isOn: $hapticsOn, tint: GameTheme.beam)
                    }

                    settingsCard(title: "关于", icon: "info.circle.fill", tint: GameTheme.horizon) {
                        settingsMiniStat(
                            icon: "app.badge.fill",
                            label: "版本",
                            value: gameAppVersionLabel,
                            tint: GameTheme.accentDeep
                        )
                        Text("水果保卫战 · 关卡难度前松后紧")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }

                    settingsCard(title: "重置", icon: "arrow.counterclockwise", tint: Color(red: 0.88, green: 0.32, blue: 0.28)) {
                        settingsActionRow(icon: "arrow.counterclockwise.circle.fill", title: "重置关卡进度", tint: GameTheme.accentDeep) {
                            maxUnlockedStage = 0
                            playingStage = 0
                            persistCareer()
                            GameHaptics.success()
                        }
                        settingsActionRow(icon: "number.circle.fill", title: "清空本局分数", tint: GameTheme.beam) {
                            score = 0
                            combo = 0
                            killsThisRun = 0
                        }
                        settingsActionRow(icon: "sum", title: "清空累计分数", tint: Color(red: 0.92, green: 0.38, blue: 0.32), destructive: true) {
                            careerScore = 0
                            UserDefaults.standard.set(0, forKey: Keys.careerScore)
                        }
                        settingsActionRow(icon: "trophy.fill", title: "清空最高分", tint: Color(red: 0.92, green: 0.38, blue: 0.32), destructive: true) {
                            highScore = 0
                            UserDefaults.standard.set(0, forKey: Keys.high)
                        }
                        settingsActionRow(icon: "trash.fill", title: "清空累计击破", tint: Color(red: 0.92, green: 0.38, blue: 0.32), destructive: true) {
                            brokenTotal = 0
                            UserDefaults.standard.set(0, forKey: Keys.broken)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(settingsSheetBackdrop)
            .navigationTitle("果园设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showSettings = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var settingsSheetBackdrop: some View {
        LinearGradient(
            colors: [
                GameTheme.skyBottom.opacity(0.95),
                Color.white.opacity(0.92),
                GameTheme.skyMid.opacity(0.35),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func settingsShareHero(stage: GameProgression.StageDefinition) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [GameTheme.accent, GameTheme.accentDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: GameTheme.accentDeep.opacity(0.35), radius: 8, y: 3)
                    Text("🍎")
                        .font(.system(size: 28))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("分享战绩")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.12))
                    Text("生成果园海报 · 一键发给好友")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.38, green: 0.30, blue: 0.24).opacity(0.72))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                settingsMiniStat(icon: "star.fill", label: "得分", value: "\(max(score, highScore))", tint: GameTheme.accentDeep)
                settingsMiniStat(icon: "leaf.fill", label: "关卡", value: stage.name, tint: GameTheme.horizon)
            }

            Button {
                presentShare()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                    Text("生成战绩海报并分享")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [GameTheme.accent, GameTheme.accentDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: GameTheme.accentDeep.opacity(0.38), radius: 12, y: 5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [GameTheme.accent.opacity(0.45), GameTheme.beam.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
        )
    }

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
    }

    private func settingsMiniStat(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.38, green: 0.30, blue: 0.24).opacity(0.62))
            }
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.12))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.16), lineWidth: 0.7)
                )
        )
    }

    private func settingsToggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.12))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
    }

    private func settingsActionRow(icon: String, title: String, tint: Color, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(destructive ? Color.red.opacity(0.85) : tint)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(destructive ? Color.red.opacity(0.88) : Color(red: 0.24, green: 0.18, blue: 0.14))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loops

    private func playSFX(_ event: GameSFX.Event) {
        if event == .shoot {
            GameSFX.shared.playShoot(
                weapon: activeStage.weapon,
                stageIndex: playingStage,
                enabled: soundOn
            )
        } else {
            GameSFX.shared.play(event, enabled: soundOn)
        }
    }

    private func startMotionLoop() {
        motionTask?.cancel()
        lastFrameTime = CACurrentMediaTime()
        motionTask = Task { @MainActor in
            while !Task.isCancelled {
                let now = CACurrentMediaTime()
                let targetFPS = isPlaying ? playFPS : idleFPS
                let frameBudget = 1.0 / targetFPS
                let rawDt = now - lastFrameTime
                lastFrameTime = now
                let dt = CGFloat(min(max(rawDt, frameBudget * 0.5), 1.0 / 20.0))
                tickMotion(dt: dt)

                let elapsed = CACurrentMediaTime() - now
                let remain = frameBudget - elapsed
                if remain > 0.001 {
                    try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
                } else {
                    await Task.yield()
                }
            }
        }
    }

    private func tickMotion(dt: CGFloat) {
        guard playSize.width > 0 else { return }
        motionFrame &+= 1
        thrustPhase += dt * (isPlaying ? 10 : 4)

        if bonusTimer > 0 {
            bonusTimer = max(0, bonusTimer - dt)
            if bonusTimer <= 0 { activeBonus = .none }
        }

        let motionMul: CGFloat = {
            if stageCelebrating { return 0.1 }
            if activeBonus == .slowFruit { return 0.52 }
            return 1
        }()

        // Stars scroll — skip every other frame while playing to cut redraw cost.
        if !isPlaying || motionFrame % 2 == 0 {
            let starMul: CGFloat = isPlaying ? 1.0 : 0.55
            for i in stars.indices {
                stars[i].position.y += stars[i].speed * dt * starMul
                if stars[i].position.y > playSize.height + 4 {
                    stars[i].position.y = -4
                    stars[i].position.x = CGFloat.random(in: 0...playSize.width)
                }
            }
        }

        let minX: CGFloat = 28
        let maxX = playSize.width - 28
        let canClampX = maxX > minX + 8
        let despawnY = shipY + 40

        var removeBubbleIds = Set<UUID>()
        var leaked: [GameBubble] = []
        for i in bubbles.indices {
            bubbles[i].phase += dt * bubbles[i].pulseSpeed
            if bubbles[i].kind == .zig {
                bubbles[i].vx = sin(bubbles[i].phase * 1.8) * bubbles[i].weaveAmp
            }
            bubbles[i].position.x += bubbles[i].vx * dt * motionMul
            bubbles[i].position.y += abs(bubbles[i].vy) * dt * motionMul

            let r = bubbles[i].size * 0.5
            if canClampX {
                if bubbles[i].position.x - r < minX {
                    bubbles[i].position.x = minX + r
                    bubbles[i].vx = abs(bubbles[i].vx)
                } else if bubbles[i].position.x + r > maxX {
                    bubbles[i].position.x = maxX - r
                    bubbles[i].vx = -abs(bubbles[i].vx)
                }
            } else {
                bubbles[i].position.x = playSize.width * 0.5
                bubbles[i].vx = 0
            }

            if isPlaying, bubbles[i].kind != .zig, motionFrame % 2 == 0 {
                bubbles[i].vx += CGFloat.random(in: -8...8) * dt
                bubbles[i].vx = max(-50, min(50, bubbles[i].vx))
            }

            let scale = isPlaying
                ? GameProgression.fallSpeedScale(stageIndex: playingStage, wave: waveStage)
                : 0.7
            let maxFall: CGFloat = {
                switch bubbles[i].kind {
                case .titan: return 28 * scale
                case .elite: return 40 * scale
                case .zig: return 58 * scale
                case .swarm: return 64 * scale
                case .normal: return 46 * scale
                }
            }()
            bubbles[i].vy = min(max(abs(bubbles[i].vy), 12 * scale), maxFall)

            if bubbles[i].position.y - r > despawnY {
                if isPlaying, !stageCelebrating {
                    leaked.append(bubbles[i])
                }
                removeBubbleIds.insert(bubbles[i].id)
            }
        }
        if !removeBubbleIds.isEmpty {
            bubbles.removeAll { removeBubbleIds.contains($0.id) }
            // Idle: keep a few orbs drifting — bail if playfield too narrow (prevents infinite loop crash).
            if !isPlaying {
                var attempts = 0
                while bubbles.count < 3, attempts < 6 {
                    let before = bubbles.count
                    spawnBubble(animated: false, prefer: .normal)
                    if bubbles.count == before { break }
                    attempts += 1
                }
            }
        }
        for leakedOrb in leaked where !stageCelebrating {
            handleLeak(leakedOrb)
        }

        if !stageCelebrating {
        // Shots + damage collisions — defer destroyOrb to avoid nested bubble mutation.
        var removeShots = Set<UUID>()
        var pendingKills: [PendingKill] = []
        for i in shots.indices {
            let prev = shots[i].position
            shots[i].position.x += shots[i].vx * dt
            shots[i].position.y -= shots[i].speed * dt
            // Only despawn after leaving the screen — never cut off at HUD / playTop.
            if shots[i].position.y < -80
                || shots[i].position.x < -40
                || shots[i].position.x > playSize.width + 40 {
                removeShots.insert(shots[i].id)
                continue
            }

            if let bIdx = bubbles.firstIndex(where: { bubble in
                laserHitsBubble(from: prev, to: shots[i].position, length: shots[i].length, bubble: bubble)
            }), bIdx < bubbles.count {
                let hitShot = shots[i]
                removeShots.insert(hitShot.id)
                let dmg = hitShot.damage
                bubbles[bIdx].hp -= dmg
                if bubbles[bIdx].hp <= 0 || motionFrame % 4 == 0 {
                    emitHitSpark(at: bubbles[bIdx].position, color: bubbles[bIdx].fruit.accent)
                }

                if bubbles[bIdx].hp <= 0 {
                    let dead = bubbles.remove(at: bIdx)
                    let blast = explosiveHit(for: hitShot, bubble: dead) ? hitShot : nil
                    pendingKills.append(PendingKill(bubble: dead, blast: blast))
                } else if isPlaying, motionFrame % 4 == 0 {
                    playSFX(.hit)
                    if hapticsOn { GameHaptics.softHit(intensity: 0.35) }
                }
            }
        }
        if !removeShots.isEmpty {
            shots.removeAll { removeShots.contains($0.id) }
        }
        for kill in pendingKills {
            destroyOrb(kill.bubble, fromShot: true, blast: kill.blast)
        }
        }

        // Blast FX decay
        if !blasts.isEmpty {
            for i in blasts.indices {
                blasts[i].radius += (92 + CGFloat(blasts[i].tier) * 24) * dt
                blasts[i].opacity = max(0, blasts[i].opacity - Double(dt) * 2.1)
            }
            blasts.removeAll { $0.opacity <= 0.02 }
        }

        tickParticles(dt: dt)
    }

    private func tickParticles(dt: CGFloat) {
        if !shards.isEmpty {
            for i in shards.indices.reversed() {
                shards[i].age += dt
                let life = max(0.08, shards[i].lifetime)
                let progress = shards[i].age / life
                if progress >= 1 {
                    shards.remove(at: i)
                    continue
                }
                shards[i].position.x += shards[i].velocity.x * dt
                shards[i].position.y += shards[i].velocity.y * dt
                shards[i].rotation += shards[i].spin * Double(dt)
                shards[i].opacity = max(0, 1 - Double(progress))
            }
        }

        if !ripples.isEmpty {
            for i in ripples.indices.reversed() {
                ripples[i].age += dt
                let life = max(0.08, ripples[i].lifetime)
                let progress = ripples[i].age / life
                if progress >= 1 {
                    ripples.remove(at: i)
                    continue
                }
                ripples[i].size = ripples[i].startSize + (ripples[i].maxSize - ripples[i].startSize) * progress
                ripples[i].opacity = max(0, 1 - Double(progress))
            }
        }

        if !floatTexts.isEmpty {
            for i in floatTexts.indices.reversed() {
                floatTexts[i].age += dt
                let life = max(0.08, floatTexts[i].lifetime)
                let progress = floatTexts[i].age / life
                if progress >= 1 {
                    floatTexts.remove(at: i)
                    continue
                }
                floatTexts[i].position.y += floatTexts[i].riseSpeed * dt
                floatTexts[i].opacity = max(0, 1 - Double(progress))
            }
        }

        if motionFrame % 60 == 0 {
            trimEffectBudgets()
            GameSFX.shared.recoverIfNeeded()
        }
    }

    private func trimEffectBudgets() {
        if shards.count > 12 { shards.removeFirst(shards.count - 12) }
        if ripples.count > 3 { ripples.removeFirst(ripples.count - 3) }
        if floatTexts.count > 3 { floatTexts.removeFirst(floatTexts.count - 3) }
        if blasts.count > 4 { blasts.removeFirst(blasts.count - 4) }
        if shots.count > 20 { shots.removeFirst(shots.count - 20) }
    }

    private func explosiveHit(for shot: LaserShot, bubble: GameBubble) -> Bool {
        guard shot.explosive else { return false }
        return GameProgression.shotExplodes(
            on: bubble.kind,
            fruitValue: bubble.fruit.value,
            stage: activeStage
        )
    }

    // MARK: - Game

    private func startGame(stage overrideStage: Int? = nil) {
        let carryLives = lives
        stopGame(keepMotion: true)
        playingStage = overrideStage.map { GameProgression.clampStage($0) } ?? maxUnlockedStage
        isPlaying = true
        if playSize.width > 0 { updatePlayfield(playSize) }
        score = 0
        combo = 0
        killsThisRun = 0
        maxComboThisRun = 0
        cleanKillStreak = 0
        activeBonus = .none
        bonusTimer = 0
        stageCelebrating = false
        stageClearSnapshot = nil
        stageClearProgress = 0
        stageClearTask?.cancel()
        stageClearTask = nil
        lives = overrideStage == nil ? maxLives : max(1, min(maxLives, carryLives))
        leakShield = leakShieldMax
        waveStage = 0
        stageClearHandled = false
        fireJammedUntil = .distantPast
        stageStartedAt = Date()
        leakFlash = false
        shots.removeAll()
        shards.removeAll()
        floatTexts.removeAll()
        bubbles.removeAll()
        shipX = playSize.width * 0.5
        shipY = defaultShipY()
        for _ in 0..<(playingStage < 5 ? 2 : 3) {
            spawnBubble(animated: true, prefer: .normal)
        }
        let stage = activeStage
        spawnFloatText("第 \(playingStage + 1) 关 · \(stage.name)", at: CGPoint(x: playSize.width * 0.5, y: shipY - 80), color: GameTheme.accentDeep, size: 15)
        spawnFloatText(stage.weapon.displayName, at: CGPoint(x: playSize.width * 0.5, y: shipY - 58), color: beamProfileNow.glow, size: 12)
        playSFX(.start)

        spawnTask = Task { @MainActor in
            while !Task.isCancelled {
                guard !stageCelebrating else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                spawnForDifficulty()
                let base = GameProgression.spawnIntervalMs(stageIndex: playingStage, wave: waveStage)
                try? await Task.sleep(nanoseconds: UInt64(base) * 1_000_000)
                if Double.random(in: 0...1) < GameProgression.extraSpawnChance(stageIndex: playingStage, wave: waveStage) {
                    spawnForDifficulty()
                }
                let cap = GameProgression.softCap(stageIndex: playingStage, wave: waveStage)
                if bubbles.count > cap {
                    if let idx = bubbles.firstIndex(where: { $0.kind == .swarm || $0.kind == .normal }) {
                        // Leaking intentional cull? Better just remove without leak penalty for cull
                        bubbles.remove(at: idx)
                    } else if let idx = bubbles.indices.first {
                        bubbles.remove(at: idx)
                    }
                }
            }
        }

        fireTask = Task { @MainActor in
            while !Task.isCancelled {
                if isPlaying, !stageCelebrating { fireLaser() }
                let interval = fireIntervalNs()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func resumePlayingLoops() {
        guard isPlaying, !stageCelebrating else { return }
        spawnTask?.cancel()
        spawnTask = Task { @MainActor in
            while !Task.isCancelled {
                guard !stageCelebrating else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                spawnForDifficulty()
                let base = GameProgression.spawnIntervalMs(stageIndex: playingStage, wave: waveStage)
                try? await Task.sleep(nanoseconds: UInt64(base) * 1_000_000)
                if Double.random(in: 0...1) < GameProgression.extraSpawnChance(stageIndex: playingStage, wave: waveStage) {
                    spawnForDifficulty()
                }
                let cap = GameProgression.softCap(stageIndex: playingStage, wave: waveStage)
                if bubbles.count > cap {
                    if let idx = bubbles.firstIndex(where: { $0.kind == .swarm || $0.kind == .normal }) {
                        bubbles.remove(at: idx)
                    } else if let idx = bubbles.indices.first {
                        bubbles.remove(at: idx)
                    }
                }
            }
        }
        fireTask?.cancel()
        fireTask = Task { @MainActor in
            while !Task.isCancelled {
                if isPlaying, !stageCelebrating { fireLaser() }
                let interval = fireIntervalNs()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopGame(keepMotion: Bool = false) {
        stageClearTask?.cancel()
        stageClearTask = nil
        stageCelebrating = false
        stageClearSnapshot = nil
        stageClearProgress = 0
        stageClearHandled = false
        stageClearFinishing = false
        cancelPendingEffectWork()
        isPlaying = false
        spawnTask?.cancel(); spawnTask = nil
        fireTask?.cancel(); fireTask = nil
        shots.removeAll()
        if score > 0 {
            careerScore += score
            persistCareer()
        }
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Keys.high)
        }
        _ = keepMotion
        if playSize.width > 0 { updatePlayfield(playSize) }
    }

    private func fireIntervalNs() -> UInt64 {
        var ns = GameProgression.fireIntervalNs(stage: activeStage)
        if activeBonus == .rapidFire {
            ns = UInt64(Double(ns) * 0.62)
        }
        return ns
    }

    private func cancelPendingEffectWork() {
        levelFlashWork?.cancel()
        levelFlashWork = nil
        leakFlashWork?.cancel()
        leakFlashWork = nil
        levelFlash = false
        leakFlash = false
    }

    private func activateBonus(_ bonus: PlayBonus, seconds: CGFloat) {
        activeBonus = bonus
        bonusTimer = seconds
        withAnimation(.easeOut(duration: 0.12)) { levelFlash = true }
        levelFlashWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) { levelFlash = false }
        }
        levelFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func handleComboMilestone() {
        guard isPlaying, !stageClearHandled, !stageCelebrating else { return }
        maxComboThisRun = max(maxComboThisRun, combo)
        let center = CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.32)
        switch combo {
        case 5:
            score += 12
            spawnFloatText("连击 ×5", at: center, color: GameTheme.accent, size: 15)
        case 10:
            score += 20
            activateBonus(.doubleScore, seconds: 7)
            spawnFloatText("赏金时刻 · 2×分数", at: center, color: GameTheme.beamHot, size: 14)
        case 15:
            score += 35
            activateBonus(.rapidFire, seconds: 5)
            spawnFloatText("火力全开", at: center, color: beamProfileNow.glow, size: 14)
        case 25:
            score += 80
            spawnFloatText("果神降临", at: center, color: .white, size: 16)
        default:
            break
        }
    }

    private func handleCleanStreak() {
        guard !stageClearHandled, !stageCelebrating else { return }
        guard cleanKillStreak > 0, cleanKillStreak.isMultiple(of: 12) else { return }
        if leakShield < leakShieldMax {
            leakShield = leakShieldMax
            spawnFloatText(
                "护盾回满",
                at: CGPoint(x: shipX, y: shipY - 72),
                color: Color(red: 0.45, green: 0.92, blue: 1.0),
                size: 13
            )
            if hapticsOn {
                GameHaptics.success()
            }
        } else if lives < maxLives {
            lives += 1
            spawnFloatText(
                "完美防守 +1❤️",
                at: CGPoint(x: shipX, y: shipY - 72),
                color: Color(red: 0.98, green: 0.35, blue: 0.42),
                size: 14
            )
            if hapticsOn {
                GameHaptics.success()
            }
        } else {
            score += 40
            spawnFloatText("无漏击破 +40", at: CGPoint(x: shipX, y: shipY - 72), color: GameTheme.beamHot, size: 13)
        }
    }

    private func handleLeak(_ bubble: GameBubble) {
        guard isPlaying, lives > 0, !stageCelebrating else { return }
        cleanKillStreak = 0
        combo = 0

        // Swarm rarely bites; titans/elites chew more shield but still not an instant heart.
        let shieldCost: Int = {
            switch bubble.kind {
            case .swarm: return Int.random(in: 0...3) == 0 ? 1 : 0
            case .titan, .elite: return 2
            case .zig: return 1
            case .normal: return 1
            }
        }()
        guard shieldCost > 0 else {
            spawnFloatText("擦过", at: bubble.position, color: .white.opacity(0.8), size: 11)
            return
        }

        if leakShield > 0 {
            leakShield = max(0, leakShield - shieldCost)
            score = max(0, score - 3)
            fireJammedUntil = Date().addingTimeInterval(0.12)
            let remain = leakShield
            spawnFloatText(
                remain > 0 ? "漏果 护盾−\(shieldCost)" : "护盾碎裂",
                at: CGPoint(x: shipX, y: shipY - 56),
                color: Color(red: 0.45, green: 0.92, blue: 1.0),
                size: 13
            )
            playSFX(.leak)
            withAnimation(.easeOut(duration: 0.08)) { leakFlash = true }
            leakFlashWork?.cancel()
            let work = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.25)) { leakFlash = false }
            }
            leakFlashWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
            if hapticsOn {
                GameHaptics.lightTap(intensity: 0.45)
            }
            return
        }

        lives -= 1
        score = max(0, score - 8)
        fireJammedUntil = Date().addingTimeInterval(0.28)
        // Soft reset: give a fresh buffer after losing a heart so mistakes don't snowball.
        leakShield = leakShieldMax
        spawnFloatText("漏果 −1❤️", at: CGPoint(x: shipX, y: shipY - 56), color: Color(red: 0.98, green: 0.35, blue: 0.42), size: 14)
        playSFX(.leak)
        withAnimation(.easeOut(duration: 0.08)) { leakFlash = true }
        leakFlashWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) { leakFlash = false }
        }
        leakFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        if hapticsOn {
            GameHaptics.warning()
        }
        if lives <= 0 {
            defenseFailed()
        }
    }

    private func defenseFailed() {
        spawnFloatText("果园失守", at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.42), color: Color(red: 0.98, green: 0.35, blue: 0.42), size: 20)
        playSFX(.gameOver)
        if hapticsOn {
            GameHaptics.error()
        }
        stopGame(keepMotion: true)
        seedIdleBubbles()
    }

    private func handleUnlockTap() {
        guard !unlockTriggered else { return }
        unlockTapCount += 1
        if hapticsOn {
            GameHaptics.lightTap(intensity: 0.55)
        }
        unlockTapResetTask?.cancel()
        unlockTapResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            unlockTapCount = 0
        }
        if unlockTapCount >= unlockTapTarget {
            unlockTapCount = 0
            unlockTapResetTask?.cancel()
            unlockTriggered = true
            onUnlocked()
        }
    }

    private func shareMessage() -> String {
        let stage = GameProgression.stage(index: max(playingStage, maxUnlockedStage))
        return """
        🍊 水果保卫战 · 关卡模式

        本局 \(score) 分 · 最高 \(highScore) 分
        第 \(stage.index + 1) 关 · \(stage.name)
        武器：\(stage.weapon.displayName)
        累计击破 \(brokenTotal) 颗 · 生涯 \(careerScore) 分

        来一起闯关守果园吧！
        """
    }

    private func presentShare() {
        guard !showShareSheet else { return }
        let stage = GameProgression.stage(index: max(playingStage, maxUnlockedStage))
        let poster = GameSharePoster(
            score: max(score, highScore),
            highScore: highScore,
            careerScore: careerScore,
            level: stage.index,
            stageName: stage.name,
            weaponName: stage.weapon.displayName,
            title: "第 \(stage.index + 1) 关 · \(stage.weapon.displayName)",
            broken: brokenTotal,
            wave: max(1, waveStage + 1),
            combo: max(combo, maxComboThisRun),
            lives: lives
        )
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        shareItems = [shareMessage(), image]
        showShareSheet = true
        if hapticsOn {
            GameHaptics.mediumTap(intensity: 0.7)
        }
    }

    private func safeSpawnX(margin: CGFloat, preferred: CGFloat? = nil) -> CGFloat {
        let minX = margin
        let maxX = playSize.width - margin
        guard maxX > minX else { return preferred ?? playSize.width * 0.5 }
        if let preferred, preferred >= minX, preferred <= maxX { return preferred }
        return CGFloat.random(in: minX...maxX)
    }

    private func emitBlast(at point: CGPoint, color: Color, tier: Int) {
        if blasts.count > 6 { blasts.removeFirst(blasts.count - 6) }
        blasts.append(
            BlastFX(
                id: UUID(),
                position: point,
                color: color,
                radius: 10,
                opacity: 1.0,
                ringWidth: tier >= 2 ? 3.5 : 2.2,
                tier: min(3, tier + 1),
                sparkAngle: Double.random(in: 0...45)
            )
        )
    }

    private func applySplash(at center: CGPoint, radius: CGFloat, damage: Int, skipID: UUID) {
        guard damage > 0, radius > 0, !stageCelebrating else { return }
        var chain: [GameBubble] = []
        for i in bubbles.indices.reversed() {
            if chain.count >= maxSplashKillsPerBlast { break }
            if bubbles[i].id == skipID { continue }
            let reach = radius + bubbles[i].size * 0.45
            let dx = bubbles[i].position.x - center.x
            let dy = bubbles[i].position.y - center.y
            guard dx * dx + dy * dy <= reach * reach else { continue }
            bubbles[i].hp -= damage
            if bubbles[i].hp <= 0 {
                chain.append(bubbles.remove(at: i))
            } else {
                emitHitSpark(at: bubbles[i].position, color: bubbles[i].fruit.accent)
            }
        }
        for orb in chain {
            destroyOrb(orb, fromShot: true, skipSplash: true)
        }
    }

    private func seedStars(in size: CGSize) {
        let sparkles: [Color] = [
            orchardTheme.starTint,
            .white,
            GameTheme.beamHot,
            GameTheme.accent,
            orchardTheme.skyWarm,
        ]
        stars = (0..<(playSize.height < 760 ? 14 : 18)).map { _ in
            StarDust(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                size: CGFloat.random(in: 1.4...3.2),
                opacity: Double.random(in: 0.22...0.62),
                speed: CGFloat.random(in: 18...52),
                tint: sparkles.randomElement() ?? .white
            )
        }
    }

    private func seedIdleBubbles() {
        bubbles.removeAll()
        shots.removeAll()
        shards.removeAll()
        ripples.removeAll()
        floatTexts.removeAll()
        var attempts = 0
        while bubbles.count < 3, attempts < 6 {
            let before = bubbles.count
            spawnBubble(animated: true, prefer: .normal)
            if bubbles.count == before { break }
            attempts += 1
        }
    }

    private func spawnForDifficulty() {
        let kind = GameProgression.pickOrbKind(stageIndex: playingStage, wave: waveStage)

        if kind == .swarm {
            let cx = safeSpawnX(margin: 60, preferred: playSize.width * 0.5)
            let topY = playTop + 12
            let count: Int = {
                if playingStage < 8 { return 2 }
                if waveStage >= 4 { return 4 }
                if waveStage >= 2 { return 3 }
                return 2
            }()
            for i in 0..<count {
                spawnBubble(
                    animated: true,
                    prefer: .swarm,
                    at: CGPoint(x: cx + CGFloat(i - 1) * 26, y: topY - CGFloat(i) * 14)
                )
            }
        } else if kind == .titan {
            if !bubbles.contains(where: { $0.kind == .titan }) {
                spawnBubble(animated: true, prefer: .titan)
            } else {
                spawnBubble(animated: true, prefer: .elite)
            }
        } else {
            spawnBubble(animated: true, prefer: kind)
        }
    }

    private func spawnBubble(animated: Bool, prefer: OrbKind, at forced: CGPoint? = nil) {
        guard playSize.width > 40 else { return }
        let fruit = GameProgression.fruit(for: activeStage, kind: prefer)

        let bs = layout.bubbleScale
        let hp = isPlaying
            ? GameProgression.bubbleHP(kind: prefer, stageIndex: playingStage, wave: waveStage)
            : max(1, prefer == .titan ? 8 : (prefer == .elite ? 4 : 1))
        let (size, weave): (CGFloat, CGFloat) = {
            switch prefer {
            case .normal: return (CGFloat.random(in: 30...48) * bs, 0)
            case .swarm: return (CGFloat.random(in: 18...26) * bs, 0)
            case .elite: return (CGFloat.random(in: 52...68) * bs, 0)
            case .zig: return (CGFloat.random(in: 28...40) * bs, CGFloat.random(in: 65...110))
            case .titan: return (CGFloat.random(in: 88...112) * bs, 0)
            }
        }()

        let spawnY = (forced?.y) ?? (playTop + 8 + CGFloat.random(in: 0...28))
        let spawnX = forced?.x ?? safeSpawnX(margin: 48)

        let scale = isPlaying
            ? GameProgression.fallSpeedScale(stageIndex: playingStage, wave: waveStage)
            : 0.65
        let fallSpeed: CGFloat = {
            let base: ClosedRange<CGFloat>
            switch prefer {
            case .titan: base = 16...24
            case .elite: base = 22...32
            case .zig: base = 34...48
            case .swarm: base = 40...56
            case .normal: base = 22...34
            }
            return CGFloat.random(in: base) * scale
        }()

        let softCap = isPlaying
            ? GameProgression.softCap(stageIndex: playingStage, wave: waveStage)
            : 4
        if bubbles.count >= softCap { return }

        let bonusVeg: VegKind? = (prefer == .normal && isPlaying && !stageCelebrating && Int.random(in: 0..<30) == 0)
            ? VegKind.randomBonus() : nil
        let isGolden = bonusVeg == nil && prefer == .normal && isPlaying && !stageCelebrating && Int.random(in: 0..<22) == 0

        var orbSize = isGolden ? size * 1.08 : size
        if bonusVeg != nil { orbSize *= 0.88 }

        let bubble = GameBubble(
            id: UUID(),
            fruit: fruit,
            bonusVeg: bonusVeg,
            kind: prefer,
            isGolden: isGolden,
            size: orbSize,
            position: CGPoint(x: spawnX, y: spawnY),
            scale: 1,
            vx: prefer == .zig ? weave * 0.4 : CGFloat.random(in: -18...18),
            vy: fallSpeed,
            phase: CGFloat.random(in: 0...(2 * .pi)),
            pulseSpeed: prefer == .titan ? CGFloat.random(in: 0.8...1.4) : CGFloat.random(in: 1.4...2.8),
            hp: hp,
            maxHp: hp,
            weaveAmp: weave
        )
        bubbles.append(bubble)
    }

    private func fireLaser() {
        guard playSize.width > 0 else { return }
        guard Date() >= fireJammedUntil else { return }
        let originY = shipY - 38 * layout.scale
        let profile = beamProfileNow
        for (dx, vx, shotDmg) in profile.volley {
            shots.append(
                LaserShot(
                    id: UUID(),
                    position: CGPoint(x: shipX + dx, y: originY),
                    speed: profile.speed,
                    length: profile.length,
                    width: profile.width,
                    vx: vx,
                    damage: shotDmg,
                    glow: profile.glow,
                    gradient: profile.gradient,
                    tier: profile.tier,
                    trailScale: profile.trailScale,
                    sparkle: profile.sparkle,
                    explosive: profile.explosive,
                    blastRadius: profile.blastRadius,
                    splashDamage: profile.splashDamage,
                    style: profile.style
                )
            )
        }
        let cap = min(24, 12 + playingStage / 3)
        if shots.count > cap {
            shots.removeFirst(shots.count - cap)
        }
        playSFX(.shoot)
    }

    /// Segment + laser length hit test so fast/multi shots don't tunnel past top fruit.
    private func laserHitsBubble(from prev: CGPoint, to curr: CGPoint, length: CGFloat, bubble: GameBubble) -> Bool {
        let hitR = bubble.size * 0.58
        let tipY = curr.y - length * 0.45
        let tip = CGPoint(x: curr.x, y: tipY)
        if pointHits(tip, bubble.position, hitR) { return true }
        if pointHits(curr, bubble.position, hitR) { return true }
        return segmentHits(prev, curr, bubble.position, hitR)
    }

    private func pointHits(_ a: CGPoint, _ b: CGPoint, _ r: CGFloat) -> Bool {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy <= r * r
    }

    private func segmentHits(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ r: CGFloat) -> Bool {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        guard len2 > 0.001 else { return pointHits(a, c, r) }
        var t = ((c.x - a.x) * abx + (c.y - a.y) * aby) / len2
        t = max(0, min(1, t))
        let px = a.x + abx * t
        let py = a.y + aby * t
        let dx = px - c.x
        let dy = py - c.y
        return dx * dx + dy * dy <= r * r
    }

    private func destroyOrb(_ bubble: GameBubble, fromShot: Bool, blast: LaserShot? = nil, skipSplash: Bool = false) {
        let explosiveHit = blast?.explosive == true && !skipSplash
        emitShatter(from: bubble, skipBurst: explosiveHit)
        if ripples.count < 4 {
            emitRipple(from: bubble)
        }
        if let blast, blast.explosive, !skipSplash {
            emitBlast(at: bubble.position, color: bubble.fruit.accent, tier: blast.tier)
            applySplash(at: bubble.position, radius: blast.blastRadius, damage: blast.splashDamage, skipID: bubble.id)
        }

        guard isPlaying else {
            if blast?.explosive == true, !skipSplash {
                playSFX(.boom)
            } else {
                playSFX(.pop)
            }
            if hapticsOn {
                GameHaptics.softHit(intensity: 0.5)
            }
            spawnBubble(animated: true, prefer: .normal)
            return
        }
        guard fromShot else { return }
        guard !stageClearHandled, !stageCelebrating else { return }

        if let veg = bubble.bonusVeg {
            if blast?.explosive == true, !skipSplash {
                playSFX(.boom)
            } else {
                playSFX(.pop)
            }
            shatterHaptic(heavy: false)
            var pts = veg.bonusPoints + min(combo, 8)
            if activeBonus == .doubleScore { pts *= 2 }
            score += pts
            spawnFloatText("蔬菜 \(veg.name) +\(pts)", at: bubble.position, color: veg.accent, size: 14)
            return
        }

        let heavy = bubble.kind == .titan || bubble.kind == .elite
        if blast?.explosive == true, !skipSplash {
            playSFX(.boom)
        } else {
            playSFX(heavy ? .bigPop : .pop)
        }

        brokenTotal += 1
        UserDefaults.standard.set(brokenTotal, forKey: Keys.broken)
        shatterHaptic(heavy: heavy)
        combo += 1
        killsThisRun += 1
        cleanKillStreak += 1
        handleComboMilestone()
        handleCleanStreak()

        let kindBonus: Int = {
            switch bubble.kind {
            case .normal: return 8
            case .swarm: return 5
            case .zig: return 16
            case .elite: return 40
            case .titan: return 110
            }
        }()
        var points = kindBonus + bubble.fruit.value / 2 + min(combo, 12) * 2
        if bubble.isGolden { points += 65 }
        if activeBonus == .doubleScore { points *= 2 }
        score += points

        if bubble.isGolden {
            spawnFloatText("✨ 幸运果 +\(points)", at: bubble.position, color: GameTheme.beamHot, size: 14)
        } else if bubble.kind == .titan || bubble.fruit.value >= 60 {
            spawnFloatText(bubble.fruit.name, at: bubble.position, color: bubble.fruit.accent, size: 16)
        } else if bubble.kind == .elite || bubble.fruit.value >= 40 {
            spawnFloatText("\(bubble.fruit.name) +\(kindBonus)", at: bubble.position, color: .white, size: 13)
        }

        updateWaveStage()
        checkStageComplete()

        if !stageCelebrating, bubbles.count < 5 + waveStage / 2 {
            spawnBubble(animated: true, prefer: .normal)
        }
    }

    private func updateWaveStage() {
        guard !stageClearHandled, !stageCelebrating else { return }
        let q = activeStage.killQuota
        guard q > 0 else { return }
        let fraction = killsThisRun * 100 / q
        let next = min(4, fraction / 25)
        guard next > waveStage else { return }
        waveStage = next
        let messages = ["果潮升温", "精英混入", "乱流来袭", "终局果涌"]
        spawnFloatText(
            messages[min(next - 1, messages.count - 1)],
            at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.28),
            color: GameTheme.beamHot,
            size: 14
        )
        playSFX(.wave)
        if Int.random(in: 0..<3) == 0 {
            let roll = Int.random(in: 0..<3)
            let bonus: PlayBonus = roll == 0 ? .slowFruit : (roll == 1 ? .rapidFire : .doubleScore)
            activateBonus(bonus, seconds: 4.5)
            spawnFloatText(
                "随机事件 · \(bonus.label)",
                at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.36),
                color: beamProfileNow.glow,
                size: 12
            )
        }
    }

    private func checkStageComplete() {
        guard !stageClearHandled, !stageCelebrating, !stageClearFinishing,
              killsThisRun >= activeStage.killQuota else { return }
        let elapsed = Date().timeIntervalSince(stageStartedAt)
        guard elapsed >= minStageSeconds else { return }
        stageClearHandled = true
        spawnTask?.cancel()
        spawnTask = nil
        fireTask?.cancel()
        fireTask = nil
        shots.removeAll()
        // Keep remaining fruits drifting slowly — gentler transition.
        activeBonus = .none
        bonusTimer = 0

        let cleared = playingStage
        let clearedStage = GameProgression.stage(index: cleared)
        if cleared >= maxUnlockedStage, cleared < GameProgression.maxStageIndex {
            maxUnlockedStage = cleared + 1
            persistCareer()
        }

        maxComboThisRun = max(maxComboThisRun, combo)
        let isFinal = cleared >= GameProgression.maxStageIndex
        let nextStage = isFinal ? nil : GameProgression.stage(index: cleared + 1)
        stageClearSnapshot = StageClearSnapshot(
            clearedIndex: cleared,
            clearedName: clearedStage.name,
            weaponName: clearedStage.weapon.displayName,
            score: score,
            maxCombo: maxComboThisRun,
            livesLeft: lives,
            grade: stageGrade(lives: lives, maxCombo: maxComboThisRun),
            nextIndex: isFinal ? nil : cleared + 1,
            nextName: nextStage?.name,
            nextWeapon: nextStage?.weapon.displayName,
            isFinal: isFinal
        )
        stageCelebrating = true
        stageClearProgress = 0
        playSFX(.levelUp)
        emitCelebrationBurst()
        if hapticsOn {
            GameHaptics.success()
        }

        stageClearTask?.cancel()
        beginStageClearCountdown(cleared: cleared, isFinal: isFinal, fromProgress: 0)
    }

    private func beginStageClearCountdown(cleared: Int, isFinal: Bool, fromProgress: CGFloat) {
        stageClearTask?.cancel()
        stageClearTask = Task { @MainActor in
            let steps = max(1, Int(stageClearDuration * 10))
            let startStep = min(steps, max(0, Int(fromProgress * CGFloat(steps))))
            if startStep > 0 {
                stageClearProgress = CGFloat(startStep) / CGFloat(steps)
            }
            for i in startStep...steps {
                guard !Task.isCancelled else { return }
                stageClearProgress = CGFloat(i) / CGFloat(steps)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            finishStageClear(cleared: cleared, isFinal: isFinal)
        }
    }

    private func skipStageClearTransition() {
        guard stageCelebrating,
              stageClearProgress >= stageClearSkipAfter / stageClearDuration,
              let snap = stageClearSnapshot else { return }
        stageClearTask?.cancel()
        finishStageClear(cleared: snap.clearedIndex, isFinal: snap.isFinal)
    }

    private func finishStageClear(cleared: Int, isFinal: Bool) {
        guard !stageClearFinishing else { return }
        stageClearFinishing = true
        stageClearTask?.cancel()
        stageClearTask = nil
        stageCelebrating = false
        stageClearSnapshot = nil
        stageClearProgress = 0
        bubbles.removeAll()
        shards.removeAll()
        blasts.removeAll()
        shots.removeAll()
        stopGame(keepMotion: true)
        if isFinal {
            seedIdleBubbles()
            spawnFloatText(
                "百果神域已征服",
                at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.35),
                color: beamProfileNow.glow,
                size: 16
            )
            stageClearFinishing = false
        } else {
            spawnFloatText(
                "休息一下，准备下一关…",
                at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.32),
                color: GameTheme.beam,
                size: 14
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                startGame(stage: cleared + 1)
                stageClearFinishing = false
            }
        }
    }

    private func emitCelebrationBurst() {
        withAnimation(.easeOut(duration: 0.25)) { levelFlash = true }
        levelFlashWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.35)) { levelFlash = false }
        }
        levelFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        guard shards.count < 14 else { return }
        let center = CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.38)
        let colors: [Color] = [GameTheme.beamHot, GameTheme.accent, GameTheme.beam, .white]
        for i in 0..<12 {
            let angle = Double(i) / 12.0 * 2 * .pi + Double.random(in: -0.2...0.2)
            let speed = CGFloat.random(in: 90...150)
            shards.append(
                ShatterShard(
                    id: UUID(),
                    color: colors[i % colors.count],
                    position: center,
                    width: CGFloat.random(in: 4...7),
                    height: CGFloat.random(in: 8...14),
                    rotation: Double.random(in: 0...360),
                    opacity: 1,
                    blur: 0.4,
                    isDrop: false,
                    isSpark: true,
                    velocity: CGPoint(x: CGFloat(cos(angle)) * speed, y: CGFloat(sin(angle)) * speed),
                    spin: Double.random(in: -180...180),
                    age: 0,
                    lifetime: 0.55
                )
            )
        }
    }

    private func spawnFloatText(_ text: String, at point: CGPoint, color: Color, size: CGFloat) {
        if floatTexts.count > 3 {
            floatTexts.removeFirst(floatTexts.count - 3)
        }
        floatTexts.append(
            FloatText(
                id: UUID(),
                text: text,
                position: point,
                color: color,
                fontSize: size,
                opacity: 1,
                age: 0,
                lifetime: 0.75,
                riseSpeed: -48
            )
        )
    }

    private func emitHitSpark(at point: CGPoint, color: Color) {
        guard ripples.count < 3 else { return }
        ripples.append(
            PopRipple(
                id: UUID(),
                position: point,
                color: color,
                size: 10,
                opacity: 0.55,
                lineWidth: 1.2,
                startSize: 10,
                maxSize: 22,
                age: 0,
                lifetime: 0.2
            )
        )
    }

    private func emitRipple(from bubble: GameBubble) {
        if bubble.kind == .normal || bubble.kind == .swarm { return }
        guard ripples.count < 4 else { return }
        let maxSize = bubble.size * (bubble.kind == .titan ? 2.2 : 1.8)
        ripples.append(
            PopRipple(
                id: UUID(),
                position: bubble.position,
                color: bubble.fruit.accent,
                size: bubble.size * 0.3,
                opacity: 0.75,
                lineWidth: bubble.kind == .titan ? 2.5 : 1.6,
                startSize: bubble.size * 0.3,
                maxSize: maxSize,
                age: 0,
                lifetime: 0.35
            )
        )
    }

    private func emitShatter(from bubble: GameBubble, skipBurst: Bool = false) {
        guard shards.count < 12 else { return }
        let heavy = bubble.kind == .titan || bubble.kind == .elite
        if !skipBurst {
            let burstTier = bubble.kind == .titan ? 2 : (bubble.kind == .elite ? 1 : 0)
            emitBlast(at: bubble.position, color: bubble.fruit.accent, tier: burstTier)
        }

        let count = bubble.kind == .titan ? 5 : (bubble.kind == .elite ? 4 : 3)
        let lifetime: CGFloat = heavy ? 0.36 : 0.28
        for i in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 70...(heavy ? 150 : 110))
            let isDrop = i % 2 == 0
            let isSpark = !isDrop && i % 3 == 0
            shards.append(
                ShatterShard(
                    id: UUID(),
                    color: isSpark ? .white : bubble.fruit.accent,
                    position: bubble.position,
                    width: isSpark
                        ? CGFloat.random(in: 2.5...4.5)
                        : (isDrop ? CGFloat.random(in: 4...8) : CGFloat.random(in: 2.5...5)),
                    height: isDrop ? 0 : CGFloat.random(in: 7...16),
                    rotation: Double.random(in: 0...360),
                    opacity: 1,
                    blur: isSpark ? 0.6 : 0,
                    isDrop: isDrop,
                    isSpark: isSpark,
                    velocity: CGPoint(
                        x: CGFloat(cos(angle)) * speed,
                        y: CGFloat(sin(angle)) * speed
                    ),
                    spin: Double.random(in: -220...220),
                    age: 0,
                    lifetime: lifetime
                )
            )
        }
    }

    private func shatterHaptic(heavy: Bool) {
        guard hapticsOn else { return }
        GameHaptics.shatter(heavy: heavy)
    }
}

// MARK: - Models

private struct GameBubble: Identifiable {
    let id: UUID
    let fruit: FruitKind
    let bonusVeg: VegKind?
    let kind: OrbKind
    let isGolden: Bool
    let size: CGFloat
    var position: CGPoint
    var scale: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var phase: CGFloat
    var pulseSpeed: CGFloat
    var hp: Int
    let maxHp: Int
    var weaveAmp: CGFloat
}

private struct LaserShot: Identifiable {
    let id: UUID
    var position: CGPoint
    let speed: CGFloat
    let length: CGFloat
    let width: CGFloat
    var vx: CGFloat
    let damage: Int
    let glow: Color
    let gradient: LinearGradient
    let tier: Int
    let trailScale: CGFloat
    let sparkle: Bool
    let explosive: Bool
    let blastRadius: CGFloat
    let splashDamage: Int
    let style: GameProgression.WeaponStyle
}

private struct BlastFX: Identifiable {
    let id: UUID
    let position: CGPoint
    let color: Color
    var radius: CGFloat
    var opacity: Double
    var ringWidth: CGFloat
    let tier: Int
    let sparkAngle: Double
}

private struct ShatterShard: Identifiable {
    let id: UUID
    let color: Color
    var position: CGPoint
    let width: CGFloat
    let height: CGFloat
    var rotation: Double
    var opacity: Double
    var blur: CGFloat
    let isDrop: Bool
    let isSpark: Bool
    var velocity: CGPoint
    var spin: Double
    var age: CGFloat
    let lifetime: CGFloat
}

private struct PopRipple: Identifiable {
    let id: UUID
    let position: CGPoint
    let color: Color
    var size: CGFloat
    var opacity: Double
    var lineWidth: CGFloat
    let startSize: CGFloat
    let maxSize: CGFloat
    var age: CGFloat
    let lifetime: CGFloat
}

private struct StarDust: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let opacity: Double
    let speed: CGFloat
    let tint: Color
}

private struct FloatText: Identifiable {
    let id: UUID
    let text: String
    var position: CGPoint
    let color: Color
    let fontSize: CGFloat
    var opacity: Double
    var age: CGFloat
    let lifetime: CGFloat
    let riseSpeed: CGFloat
}

// MARK: - Share poster

private struct GameSharePoster: View {
    let score: Int
    let highScore: Int
    let careerScore: Int
    let level: Int
    let stageName: String
    let weaponName: String
    let title: String
    let broken: Int
    let wave: Int
    let combo: Int
    let lives: Int

    private let posterW: CGFloat = 360
    private let posterH: CGFloat = 540

    var body: some View {
        ZStack {
            // Orchard sky
            LinearGradient(
                colors: [
                    Color(red: 0.32, green: 0.55, blue: 0.94),
                    Color(red: 0.72, green: 0.78, blue: 0.98),
                    Color(red: 1.0, green: 0.78, blue: 0.52),
                    Color(red: 0.22, green: 0.52, blue: 0.32),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: posterW, height: posterH)

            Circle()
                .fill(Color(red: 1, green: 0.94, blue: 0.62).opacity(0.55))
                .frame(width: 140, height: 140)
                .blur(radius: 2)
                .offset(x: posterW * 0.28, y: -posterH * 0.28)

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 200, height: 200)
                .offset(x: -posterW * 0.32, y: posterH * 0.22)

            // Ground band
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.12, green: 0.38, blue: 0.22).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: posterH * 0.28)
            }

            VStack(spacing: 0) {
                // Header bar
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.55, blue: 0.18), Color(red: 0.90, green: 0.34, blue: 0.14)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Text("🍎")
                            .font(.system(size: 24))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("水果保卫战")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Orchard Defense")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text("第 \(level + 1) 关")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Text(stageName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
                    )
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Score hero
                VStack(spacing: 6) {
                    Text("\(score)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    Text("本局得分")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(weaponName)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.18)))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                )
                .padding(.horizontal, 20)

                // Stats grid
                HStack(spacing: 10) {
                    posterStatTile(icon: "trophy.fill", label: "最高", value: "\(highScore)", tint: Color(red: 1, green: 0.82, blue: 0.35))
                    posterStatTile(icon: "sum", label: "生涯", value: "\(careerScore)", tint: Color(red: 0.45, green: 0.98, blue: 0.62))
                    posterStatTile(icon: "sparkles", label: "击破", value: "\(broken)", tint: Color(red: 1, green: 0.55, blue: 0.18))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                HStack(spacing: 10) {
                    posterBadge(icon: "heart.fill", text: "生命 \(lives)", tint: Color(red: 0.98, green: 0.35, blue: 0.42))
                    posterBadge(icon: "flag.fill", text: "第 \(wave) 波", tint: Color(red: 0.55, green: 0.88, blue: 0.98))
                    if combo > 1 {
                        posterBadge(icon: "flame.fill", text: "×\(combo)", tint: Color(red: 1, green: 0.55, blue: 0.18))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 0)

                // Footer
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("🍊").font(.system(size: 16))
                        Text("🍌").font(.system(size: 16))
                        Text("🍇").font(.system(size: 16))
                        Text("🥭").font(.system(size: 16))
                        Text("🍉").font(.system(size: 16))
                    }
                    Text("来果园一起守防线！")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                    Text("BashX · 水果保卫战")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.bottom, 22)
            }
        }
        .frame(width: posterW, height: posterH)
        .background(Color(red: 0.22, green: 0.52, blue: 0.32))
    }

    private func posterStatTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
                )
        )
    }

    private func posterBadge(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.28))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
        )
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
