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
    @State private var floatTexts: [FloatText] = []
    @State private var score = 0
    @State private var brokenTotal = UserDefaults.standard.integer(forKey: Keys.broken)
    @State private var highScore = UserDefaults.standard.integer(forKey: Keys.high)
    @State private var combo = 0
    @State private var shipLevel = 0
    @State private var shipXP = 0
    @State private var killsThisRun = 0
    @State private var lives = 3
    @State private var waveStage = 0
    @State private var isPlaying = false
    @State private var showSettings = false
    @State private var hapticsOn = true
    @State private var soundOn = UserDefaults.standard.object(forKey: Keys.sound) as? Bool ?? true
    @State private var shipX: CGFloat = 0
    @State private var shipReady = false
    @State private var spawnTask: Task<Void, Never>?
    @State private var motionTask: Task<Void, Never>?
    @State private var fireTask: Task<Void, Never>?
    @State private var unlockTriggered = false
    @State private var unlockTapCount = 0
    @State private var unlockTapResetTask: Task<Void, Never>?
    @State private var playSize: CGSize = .zero
    @State private var playTop: CGFloat = 120
    @State private var playBottom: CGFloat = 120
    @State private var stars: [StarDust] = []
    @State private var thrustPhase: CGFloat = 0
    @State private var levelFlash = false
    @State private var leakFlash = false
    @State private var fireJammedUntil: Date = .distantPast
    @State private var startPulse = false
    @State private var pausedByBackground = false
    private let maxLives = 5

    private enum Keys {
        static let broken = "disguise.colorPop.brokenTotal"
        static let high = "disguise.colorPop.high"
        static let sound = "disguise.game.soundOn"
    }

    /// Unified casual-arcade palette for the disguise mini-game.
    private enum GameTheme {
        static let skyTop = Color(red: 0.42, green: 0.62, blue: 0.98)
        static let skyMid = Color(red: 0.78, green: 0.58, blue: 0.96)
        static let skyBottom = Color(red: 1.0, green: 0.82, blue: 0.58)
        static let horizon = Color(red: 0.38, green: 0.72, blue: 0.42)
        static let ground = Color(red: 0.22, green: 0.48, blue: 0.28)
        static let hudGlass = Color.white.opacity(0.16)
        static let hudStroke = Color.white.opacity(0.28)
        static let accent = Color(red: 1.0, green: 0.58, blue: 0.22)
        static let accentDeep = Color(red: 0.92, green: 0.38, blue: 0.18)
        static let beam = Color(red: 0.35, green: 0.88, blue: 0.48)
        static let beamHot = Color(red: 1.0, green: 0.78, blue: 0.28)
        static let shipBody = Color(red: 0.98, green: 0.72, blue: 0.28)
        static let shipWing = Color(red: 0.42, green: 0.78, blue: 0.38)
        static let shipCockpit = Color(red: 0.55, green: 0.88, blue: 0.98)
    }

    private var shipY: CGFloat {
        max(playSize.height - playBottom + 28, playSize.height * 0.82)
    }

    private var difficulty: Int {
        // Slow climb — wave stage matters more than raw score
        max(1, 1 + waveStage + score / 220 + shipLevel / 4 + killsThisRun / 18)
    }

    /// XP needed to go from `level` → `level + 1` (steady, not brutal).
    private func xpToAdvance(from level: Int) -> Int {
        36 + level * 28 + level * level * 8
    }

    private var shipTitle: String {
        switch shipLevel {
        case 0: return "护果新手"
        case 1: return "果园哨兵"
        case 2: return "果汁炮手"
        case 3: return "双管护卫"
        case 4: return "丰收守卫"
        case 5...9: return "果园队长"
        case 10...19: return "果王卫士"
        default: return "传奇护果官"
        }
    }

    /// Visual size soft-cap so the ship stays on screen at high levels.
    private var shipVisualLevel: CGFloat {
        CGFloat(min(shipLevel, 15))
    }

    var body: some View {
        ZStack {
            gameBackdrop.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    orchardSilhouette(in: geo.size)
                        .allowsHitTesting(false)

                    ForEach(stars) { star in
                        Circle()
                            .fill(star.tint.opacity(star.opacity))
                            .frame(width: star.size, height: star.size)
                            .position(star.position)
                            .allowsHitTesting(false)
                    }

                    ForEach(ripples) { ripple in
                        Circle()
                            .stroke(ripple.color.opacity(ripple.opacity), lineWidth: ripple.lineWidth)
                            .frame(width: ripple.size, height: ripple.size)
                            .position(ripple.position)
                            .allowsHitTesting(false)
                    }

                    ForEach(shards) { shard in
                        Capsule()
                            .fill(shard.color)
                            .frame(width: shard.width, height: shard.height)
                            .rotationEffect(.degrees(shard.rotation))
                            .opacity(shard.opacity)
                            .position(shard.position)
                            .allowsHitTesting(false)
                    }

                    ForEach(bubbles) { bubble in
                        fruitView(bubble)
                            .position(bubble.position)
                            .zIndex(Double(bubble.size))
                            .allowsHitTesting(false)
                    }

                    ForEach(shots) { shot in
                        Capsule()
                            .fill(shot.gradient)
                            .frame(width: shot.width, height: shot.length)
                            .shadow(color: shot.glow, radius: 5)
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
                        shipView
                            .position(x: shipX, y: shipY)
                            .allowsHitTesting(false)
                    }

                    if levelFlash {
                        GameTheme.beamHot.opacity(0.18).ignoresSafeArea().allowsHitTesting(false)
                    }

                    // Drag only in the play band — never cover HUD / bottom controls
                    if playSize.height > playTop + playBottom + 40 {
                        let bandH = playSize.height - playTop - playBottom
                        Color.clear
                            .frame(width: playSize.width, height: bandH)
                            .contentShape(Rectangle())
                            .position(x: playSize.width * 0.5, y: playTop + bandH * 0.5)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard shipReady else { return }
                                        let minX: CGFloat = 36
                                        let maxX = max(minX + 1, playSize.width - 36)
                                        // Convert local pad coords → screen X
                                        let globalX = value.location.x
                                        shipX = min(max(globalX, minX), maxX)
                                    }
                            )
                    }
                }
                .onAppear {
                    updatePlayfield(geo.size)
                    if !shipReady {
                        shipX = geo.size.width * 0.5
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
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if !isPlaying {
                    VStack(spacing: 12) {
                        homeCard
                            .onTapGesture { handleUnlockTap() }
                        bottomBar
                    }
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    bottomBar
                        .padding(.bottom, 26)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isPlaying)
            .zIndex(20)

            if leakFlash {
                Color.red.opacity(0.28)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDisappear {
            stopGame()
            motionTask?.cancel()
            motionTask = nil
            fireTask?.cancel()
            unlockTapResetTask?.cancel()
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                startPulse = true
            }
        }
        .onChange(of: soundOn) { on in
            UserDefaults.standard.set(on, forKey: Keys.sound)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                pausedByBackground = isPlaying
                // Drop FX when backgrounded so the NE / CPU cools down.
                shards.removeAll()
                ripples.removeAll()
                floatTexts.removeAll()
                shots.removeAll()
                motionTask?.cancel()
                motionTask = nil
                spawnTask?.cancel()
                spawnTask = nil
                fireTask?.cancel()
                fireTask = nil
            } else {
                startMotionLoop()
                if pausedByBackground, isPlaying {
                    resumePlayingLoops()
                }
                pausedByBackground = false
            }
        }
    }

    private func updatePlayfield(_ size: CGSize) {
        playSize = size
        let insets = keyWindowSafeInsets()
        playTop = insets.top + (isPlaying ? 36 : 92)
        playBottom = max(insets.bottom, 12) + (isPlaying ? 58 : 118)
        if !shipReady {
            shipX = size.width * 0.5
            shipReady = true
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
                colors: [GameTheme.skyTop, GameTheme.skyMid, GameTheme.skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.white.opacity(0.22), Color.clear],
                center: UnitPoint(x: 0.72, y: 0.12),
                startRadius: 8,
                endRadius: 220
            )

            RadialGradient(
                colors: [GameTheme.accent.opacity(0.14), Color.clear],
                center: UnitPoint(x: 0.18, y: 0.78),
                startRadius: 12,
                endRadius: 260
            )

            LinearGradient(
                colors: [Color.clear, GameTheme.horizon.opacity(0.35), GameTheme.ground.opacity(0.55)],
                startPoint: UnitPoint(x: 0.5, y: 0.62),
                endPoint: .bottom
            )
        }
    }

    private func orchardSilhouette(in size: CGSize) -> some View {
        let groundY = size.height * 0.88
        return ZStack {
            Ellipse()
                .fill(GameTheme.ground.opacity(0.28))
                .frame(width: size.width * 1.15, height: size.height * 0.22)
                .position(x: size.width * 0.5, y: groundY + size.height * 0.04)

            HStack(alignment: .bottom, spacing: size.width * 0.06) {
                bush(height: 54, width: 72)
                bush(height: 38, width: 56)
                bush(height: 62, width: 84)
                bush(height: 42, width: 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 18)
            .padding(.bottom, max(12, size.height * 0.06))
            .opacity(0.42)
        }
        .frame(width: size.width, height: size.height)
    }

    private func bush(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(GameTheme.ground.opacity(0.85))
                .frame(width: width * 0.18, height: height * 0.42)
            Circle()
                .fill(GameTheme.horizon.opacity(0.9))
                .frame(width: width * 0.42, height: width * 0.42)
                .offset(x: -width * 0.18, y: -height * 0.18)
            Circle()
                .fill(GameTheme.horizon.opacity(0.95))
                .frame(width: width * 0.5, height: width * 0.5)
                .offset(y: -height * 0.24)
            Circle()
                .fill(GameTheme.horizon.opacity(0.88))
                .frame(width: width * 0.4, height: width * 0.4)
                .offset(x: width * 0.2, y: -height * 0.16)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    private func fruitView(_ bubble: GameBubble) -> some View {
        let hpRatio = CGFloat(bubble.hp) / CGFloat(max(1, bubble.maxHp))
        let emojiSize = bubble.size * (bubble.kind == .titan ? 0.58 : 0.64)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            bubble.fruit.accent.opacity(0.95),
                            bubble.fruit.accent.opacity(0.55),
                            bubble.fruit.accent.opacity(0.28),
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 2,
                        endRadius: bubble.size * 0.62
                    )
                )
                .frame(width: bubble.size * 1.08, height: bubble.size * 1.08)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.2)
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: bubble.size * 0.22, height: bubble.size * 0.22)
                        .offset(x: bubble.size * 0.16, y: bubble.size * 0.14)
                }

            Text(bubble.fruit.emoji)
                .font(.system(size: emojiSize))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)

            if bubble.maxHp > 1 {
                Circle()
                    .trim(from: 0, to: hpRatio)
                    .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    .frame(width: bubble.size * 1.16, height: bubble.size * 1.16)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: bubble.fruit.accent.opacity(0.35), radius: 2)
            }

            if bubble.kind == .titan {
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 2.5)
                    .frame(width: bubble.size * 1.22, height: bubble.size * 1.22)
            }
        }
        .frame(width: bubble.size * 1.28, height: bubble.size * 1.28)
        .scaleEffect(bubble.scale)
        .shadow(color: bubble.fruit.accent.opacity(0.35), radius: 8, y: 4)
    }

    private var shipView: some View {
        let accent = GameTheme.shipBody
        let wing = GameTheme.shipWing
        let scale: CGFloat = 0.92 + shipVisualLevel * 0.03

        return ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [GameTheme.beamHot, GameTheme.accentDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 22)
                .offset(y: 32)
                .opacity(0.85)

            Path { path in
                let wingSpan = 15 + shipVisualLevel * 1.5
                path.move(to: CGPoint(x: 32, y: 18))
                path.addLine(to: CGPoint(x: 32 - wingSpan, y: 34))
                path.addLine(to: CGPoint(x: 32 - wingSpan * 0.35, y: 28))
                path.addLine(to: CGPoint(x: 28, y: 22))
                path.closeSubpath()
                path.move(to: CGPoint(x: 32, y: 18))
                path.addLine(to: CGPoint(x: 32 + wingSpan, y: 34))
                path.addLine(to: CGPoint(x: 32 + wingSpan * 0.35, y: 28))
                path.addLine(to: CGPoint(x: 36, y: 22))
                path.closeSubpath()
            }
            .fill(wing.opacity(0.92))
            .frame(width: 64, height: 48)
            .shadow(color: wing.opacity(0.35), radius: 4, y: 2)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), accent, GameTheme.accentDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 20 + shipVisualLevel * 0.35, height: 32 + shipVisualLevel * 0.5)
                .overlay(
                    Capsule()
                        .fill(GameTheme.shipCockpit.opacity(0.9))
                        .frame(width: 10, height: 14)
                        .offset(y: -6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                )
        }
        .frame(width: 78, height: 72)
        .scaleEffect(scale)
        .shadow(color: GameTheme.accentDeep.opacity(0.28), radius: 8, y: 4)
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [GameTheme.accent, GameTheme.accentDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: GameTheme.accentDeep.opacity(0.35), radius: 6, y: 3)
                        Text("🍎")
                            .font(.system(size: 22))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("水果保卫战")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.28, green: 0.22, blue: 0.18))
                        Text(isPlaying ? "守住果园 · 优先击破大果" : "拖动护果机，击落来袭水果")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.72))
                    }
                }

                Spacer(minLength: 8)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.32, green: 0.26, blue: 0.22))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(GameTheme.hudGlass)
                                .overlay(Circle().strokeBorder(GameTheme.hudStroke, lineWidth: 0.8))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }

            HStack(spacing: 8) {
                scoreChip
                levelChip
                if isPlaying {
                    livesChip
                    if combo > 1 {
                        comboChip
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        )
        .padding(.horizontal, 4)
    }

    /// Minimal transparent stats while playing — does not block falling fruit.
    private var playTopHUD: some View {
        HStack(spacing: 8) {
            playStatPill(icon: "star.fill", text: "\(score)", tint: GameTheme.accentDeep)
            playStatPill(icon: "arrow.up.circle.fill", text: "Lv.\(shipLevel)", tint: GameTheme.beam)
            playLivesPill
            if combo > 1 {
                playStatPill(icon: "flame.fill", text: "×\(combo)", tint: GameTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .overlay(alignment: .trailing) {
            playSettingsButton
                .padding(.trailing, 4)
        }
    }

    private func playStatPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.22))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
        )
    }

    private var playLivesPill: some View {
        HStack(spacing: 3) {
            ForEach(0..<maxLives, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(i < lives ? Color(red: 0.98, green: 0.35, blue: 0.42) : .white.opacity(0.35))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6))
        )
        .accessibilityLabel("生命 \(lives)")
    }

    private var playSettingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6))
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private var scoreChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GameTheme.accentDeep)
            VStack(alignment: .leading, spacing: 0) {
                Text("分数")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.55))
                Text("\(score)")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(red: 0.24, green: 0.18, blue: 0.14))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(chipBackground(tint: GameTheme.accent))
    }

    private var levelChip: some View {
        let need = xpToAdvance(from: shipLevel)
        let progress = need > 0 ? min(1, CGFloat(shipXP) / CGFloat(need)) : 0
        return HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Lv.\(shipLevel)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(GameTheme.accentDeep)
                    Text(shipTitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [GameTheme.beamHot, GameTheme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, g.size.width * progress))
                    }
                }
                .frame(width: 64, height: 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(chipBackground(tint: GameTheme.beam))
    }

    private var livesChip: some View {
        HStack(spacing: 3) {
            ForEach(0..<maxLives, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(i < lives ? Color(red: 0.98, green: 0.35, blue: 0.42) : Color.black.opacity(0.12))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(chipBackground(tint: Color(red: 0.98, green: 0.35, blue: 0.42)))
        .accessibilityLabel("防线 \(lives)")
    }

    private var comboChip: some View {
        Text("×\(combo)")
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(GameTheme.accentDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(chipBackground(tint: GameTheme.accent))
    }

    private func chipBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.7)
            )
    }

    private var homeCard: some View {
        VStack(spacing: 4) {
            Text("🍊 果园防线")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.28, green: 0.22, blue: 0.18))
            Text("5 点生命 · 优先清快果与大果")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.24).opacity(0.68))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.5))
                .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        )
    }

    private var bottomBar: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                if isPlaying {
                    stopGame()
                    seedIdleBubbles()
                } else {
                    startGame()
                }
            }
            if playSize.width > 0 { updatePlayfield(playSize) }
        } label: {
            ZStack {
                if !isPlaying {
                    Capsule(style: .continuous)
                        .fill(GameTheme.accent.opacity(startPulse ? 0.28 : 0.14))
                        .scaleEffect(startPulse ? 1.08 : 1.0)
                        .allowsHitTesting(false)
                }

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isPlaying
                                ? [Color(red: 0.92, green: 0.32, blue: 0.38), Color(red: 0.78, green: 0.22, blue: 0.32)]
                                : [GameTheme.accent, GameTheme.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    )
                    .shadow(color: GameTheme.accentDeep.opacity(isPlaying ? 0.22 : 0.38), radius: 10, y: 4)

                HStack(spacing: 6) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: isPlaying ? 9 : 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text(isPlaying ? "结束" : "开始游戏")
                        .font(.system(size: isPlaying ? 12 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: isPlaying ? 88 : 140, height: isPlaying ? 34 : 40)
            .compositingGroup()
        }
        .buttonStyle(.plain)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("游戏音效", isOn: $soundOn)
                    Toggle("破碎震感", isOn: $hapticsOn)
                } header: {
                    Text("手感")
                }

                Section {
                    LabeledContent("护果机等级", value: "Lv.\(shipLevel)")
                    LabeledContent("升级经验", value: "\(shipXP)/\(xpToAdvance(from: shipLevel))")
                    LabeledContent("本局波次", value: "第 \(waveStage + 1) 波")
                    LabeledContent("生命", value: "\(lives)/\(maxLives)")
                    LabeledContent("本局分数", value: "\(score)")
                    LabeledContent("累计击破", value: "\(brokenTotal)")
                    LabeledContent("历史最高", value: "\(highScore)")
                } header: {
                    Text("战绩")
                } footer: {
                    Text("升级靠经验慢慢涨。漏掉水果会扣生命，生命归零本局结束。新水果种类会随波次逐步出现。")
                }

                Section {
                    Button {
                        shipLevel = 0
                        shipXP = 0
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("重置护果机等级", systemImage: "arrow.counterclockwise.circle")
                    }
                    Button {
                        score = 0
                        combo = 0
                        killsThisRun = 0
                        shipXP = 0
                    } label: {
                        Label("清空本局分数", systemImage: "number")
                    }
                    Button(role: .destructive) {
                        highScore = 0
                        UserDefaults.standard.set(0, forKey: Keys.high)
                    } label: {
                        Label("清空最高分", systemImage: "trophy")
                    }
                    Button(role: .destructive) {
                        brokenTotal = 0
                        UserDefaults.standard.set(0, forKey: Keys.broken)
                    } label: {
                        Label("清空累计击破", systemImage: "trash")
                    }
                } header: {
                    Text("重置")
                }
            }
            .navigationTitle("水果保卫战")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Loops

    private func playSFX(_ event: GameSFX.Event) {
        GameSFX.shared.play(event, enabled: soundOn)
    }

    private func startMotionLoop() {
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            while !Task.isCancelled {
                // ~24fps play / ~15fps idle — smooth enough, cooler than 30fps.
                let playing = isPlaying
                let dt: CGFloat = playing ? (1.0 / 24.0) : (1.0 / 15.0)
                let sleepNs: UInt64 = playing ? 42_000_000 : 66_000_000
                tickMotion(dt: dt)
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    private func tickMotion(dt: CGFloat) {
        guard playSize.width > 0 else { return }
        motionFrame &+= 1
        thrustPhase += dt * (isPlaying ? 10 : 4)

        // Stars scroll every frame (lightweight).
        let starMul: CGFloat = isPlaying ? 1.0 : 0.55
        for i in stars.indices {
            stars[i].position.y += stars[i].speed * dt * starMul
            if stars[i].position.y > playSize.height + 4 {
                stars[i].position.y = -4
                stars[i].position.x = CGFloat.random(in: 0...playSize.width)
            }
        }

        let minX: CGFloat = 28
        let maxX = playSize.width - 28
        let despawnY = shipY + 40

        var removeBubbleIds = Set<UUID>()
        var leaked: [GameBubble] = []
        for i in bubbles.indices {
            bubbles[i].phase += dt * bubbles[i].pulseSpeed
            if bubbles[i].kind == .zig {
                bubbles[i].vx = sin(bubbles[i].phase * 1.8) * bubbles[i].weaveAmp
            }
            bubbles[i].position.x += bubbles[i].vx * dt
            bubbles[i].position.y += abs(bubbles[i].vy) * dt

            let r = bubbles[i].size * 0.5
            if bubbles[i].position.x - r < minX {
                bubbles[i].position.x = minX + r
                bubbles[i].vx = abs(bubbles[i].vx)
            } else if bubbles[i].position.x + r > maxX {
                bubbles[i].position.x = maxX - r
                bubbles[i].vx = -abs(bubbles[i].vx)
            }

            if isPlaying, bubbles[i].kind != .zig, motionFrame % 2 == 0 {
                bubbles[i].vx += CGFloat.random(in: -8...8) * dt
                bubbles[i].vx = max(-50, min(50, bubbles[i].vx))
            }

            let maxFall: CGFloat = {
                switch bubbles[i].kind {
                case .titan: return isPlaying ? 42 + CGFloat(difficulty) : 28
                case .elite: return isPlaying ? 62 + CGFloat(difficulty) : 44
                case .zig: return isPlaying ? 88 + CGFloat(difficulty) : 58
                case .swarm: return isPlaying ? 100 + CGFloat(difficulty) * 2 : 70
                case .normal: return isPlaying ? 72 + CGFloat(difficulty) * 3 : 52
                }
            }()
            bubbles[i].vy = min(max(abs(bubbles[i].vy), 16), maxFall)

            if bubbles[i].position.y - r > despawnY {
                if isPlaying {
                    leaked.append(bubbles[i])
                }
                removeBubbleIds.insert(bubbles[i].id)
            }
        }
        if !removeBubbleIds.isEmpty {
            bubbles.removeAll { removeBubbleIds.contains($0.id) }
            // Idle: keep a few orbs drifting so the camouflage screen never freezes.
            if !isPlaying {
                while bubbles.count < 3 {
                    spawnBubble(animated: false, prefer: .normal)
                }
            }
        }
        for leakedOrb in leaked {
            handleLeak(leakedOrb)
        }

        // Shots + damage collisions
        var removeShots = Set<UUID>()
        for i in shots.indices {
            shots[i].position.x += shots[i].vx * dt
            shots[i].position.y -= shots[i].speed * dt
            if shots[i].position.y < playTop - 24 || shots[i].position.x < -20 || shots[i].position.x > playSize.width + 20 {
                removeShots.insert(shots[i].id)
                continue
            }

            if let bIdx = bubbles.firstIndex(where: { bubble in
                let dx = shots[i].position.x - bubble.position.x
                let dy = shots[i].position.y - bubble.position.y
                let hitR = bubble.size * 0.5
                return dx * dx + dy * dy <= hitR * hitR
            }) {
                removeShots.insert(shots[i].id)
                let dmg = shots[i].damage
                bubbles[bIdx].hp -= dmg
                if bubbles[bIdx].hp <= 0 || motionFrame % 3 == 0 {
                    emitHitSpark(at: bubbles[bIdx].position, color: bubbles[bIdx].fruit.accent)
                }

                if bubbles[bIdx].hp <= 0 {
                    let dead = bubbles.remove(at: bIdx)
                    destroyOrb(dead, fromShot: true)
                } else if isPlaying {
                    playSFX(.hit)
                    if hapticsOn {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                    }
                }
            }
        }
        if !removeShots.isEmpty {
            shots.removeAll { removeShots.contains($0.id) }
        }

        // Nudge @State so ForEach positions always refresh.
        if motionFrame % 2 == 0 {
            bubbles = bubbles
            shots = shots
            stars = stars
        }
    }

    // MARK: - Game

    private func startGame() {
        stopGame(keepMotion: true)
        isPlaying = true
        if playSize.width > 0 { updatePlayfield(playSize) }
        score = 0
        combo = 0
        shipLevel = 0
        shipXP = 0
        killsThisRun = 0
        lives = maxLives
        waveStage = 0
        fireJammedUntil = .distantPast
        leakFlash = false
        shots.removeAll()
        shards.removeAll()
        floatTexts.removeAll()
        bubbles.removeAll()
        shipX = playSize.width * 0.5
        for _ in 0..<4 {
            spawnBubble(animated: true, prefer: .normal)
        }
        spawnFloatText("果园开战", at: CGPoint(x: playSize.width * 0.5, y: shipY - 80), color: GameTheme.accentDeep, size: 15)
        playSFX(.start)

        spawnTask = Task { @MainActor in
            while !Task.isCancelled {
                spawnForDifficulty()
                // Slower early waves; pressure rises with stage, not ship power
                let base = max(340, 920 - waveStage * 70 - difficulty * 18)
                try? await Task.sleep(nanoseconds: UInt64(base) * 1_000_000)
                if waveStage >= 4, Int.random(in: 0...4) == 0 {
                    spawnForDifficulty()
                }
                if bubbles.count > 8 + min(waveStage, 2) {
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
                if isPlaying { fireLaser() }
                let interval = fireIntervalNs()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func resumePlayingLoops() {
        guard isPlaying else { return }
        spawnTask?.cancel()
        spawnTask = Task { @MainActor in
            while !Task.isCancelled {
                spawnForDifficulty()
                let base = max(340, 920 - waveStage * 70 - difficulty * 18)
                try? await Task.sleep(nanoseconds: UInt64(base) * 1_000_000)
                if waveStage >= 4, Int.random(in: 0...4) == 0 {
                    spawnForDifficulty()
                }
                if bubbles.count > 8 + min(waveStage, 2) {
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
                if isPlaying { fireLaser() }
                let interval = fireIntervalNs()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopGame(keepMotion: Bool = false) {
        isPlaying = false
        spawnTask?.cancel(); spawnTask = nil
        fireTask?.cancel(); fireTask = nil
        shots.removeAll()
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Keys.high)
        }
        _ = keepMotion
        if playSize.width > 0 { updatePlayfield(playSize) }
    }

    private func fireIntervalNs() -> UInt64 {
        let ns = 320_000_000 - min(shipLevel, 18) * 7_000_000
        return UInt64(max(160_000_000, ns))
    }

    private func handleLeak(_ bubble: GameBubble) {
        guard isPlaying, lives > 0 else { return }
        // Swarm leaks sting less — one life shared across a pack feels fairer
        let cost = bubble.kind == .swarm ? (Int.random(in: 0...2) == 0 ? 1 : 0) : 1
        guard cost > 0 else {
            combo = 0
            spawnFloatText("擦过", at: bubble.position, color: .white.opacity(0.8), size: 11)
            return
        }
        lives -= cost
        combo = 0
        score = max(0, score - 8)
        fireJammedUntil = Date().addingTimeInterval(0.32)
        spawnFloatText("漏果 −1", at: CGPoint(x: shipX, y: shipY - 56), color: Color(red: 0.98, green: 0.35, blue: 0.42), size: 14)
        playSFX(.leak)
        withAnimation(.easeOut(duration: 0.08)) { leakFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.25)) { leakFlash = false }
        }
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        if lives <= 0 {
            defenseFailed()
        }
    }

    private func defenseFailed() {
        spawnFloatText("果园失守", at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.42), color: Color(red: 0.98, green: 0.35, blue: 0.42), size: 20)
        playSFX(.gameOver)
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        stopGame(keepMotion: true)
        seedIdleBubbles()
    }

    private func handleUnlockTap() {
        guard !unlockTriggered else { return }
        unlockTapCount += 1
        if hapticsOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        }
        unlockTapResetTask?.cancel()
        unlockTapResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            unlockTapCount = 0
        }
        if unlockTapCount >= 5 {
            unlockTapCount = 0
            unlockTapResetTask?.cancel()
            unlockTriggered = true
            onUnlocked()
        }
    }

    private func seedStars(in size: CGSize) {
        let sparkles: [Color] = [
            .white,
            GameTheme.beamHot,
            GameTheme.accent,
            GameTheme.beam,
            Color(red: 1.0, green: 0.92, blue: 0.72),
        ]
        stars = (0..<18).map { _ in
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
        for _ in 0..<3 {
            spawnBubble(animated: true, prefer: .normal)
        }
    }

    private func spawnForDifficulty() {
        let roll = Int.random(in: 0..<100)
        let kind: OrbKind
        // Unlock kinds gradually — early game is almost only normals
        switch waveStage {
        case 0:
            kind = .normal
        case 1:
            kind = roll < 78 ? .normal : .swarm
        case 2:
            kind = roll < 58 ? .normal : (roll < 82 ? .swarm : .zig)
        case 3:
            kind = roll < 48 ? .normal : (roll < 68 ? .swarm : (roll < 86 ? .zig : .elite))
        default:
            kind = roll < 36 ? .normal : (roll < 54 ? .swarm : (roll < 70 ? .zig : (roll < 88 ? .elite : .titan)))
        }

        if kind == .swarm {
            let cx = CGFloat.random(in: 60...(playSize.width - 60))
            let topY = playTop - 10
            let count = waveStage >= 4 ? 3 : 2
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
        let fruit = FruitKind.random(for: prefer)

        let (size, hp, weave): (CGFloat, Int, CGFloat) = {
            switch prefer {
            case .normal:
                return (CGFloat.random(in: 30...48), 1, 0)
            case .swarm:
                return (CGFloat.random(in: 18...26), 1, 0)
            case .elite:
                return (CGFloat.random(in: 52...68), 3 + waveStage / 2, 0)
            case .zig:
                return (CGFloat.random(in: 28...40), 2, CGFloat.random(in: 55...95))
            case .titan:
                return (CGFloat.random(in: 88...112), 10 + waveStage * 2, 0)
            }
        }()

        let spawnY = (forced?.y) ?? (playTop - size * 0.6 - CGFloat.random(in: 0...36))
        let spawnX = (forced?.x) ?? CGFloat.random(in: 48...(playSize.width - 48))

        let fallSpeed: CGFloat = {
            switch prefer {
            case .titan: return isPlaying ? CGFloat.random(in: 16...26) : CGFloat.random(in: 12...20)
            case .elite: return isPlaying ? CGFloat.random(in: 24...36) : CGFloat.random(in: 18...28)
            case .zig: return isPlaying ? CGFloat.random(in: 40...60) : CGFloat.random(in: 30...44)
            case .swarm: return isPlaying ? CGFloat.random(in: 52...78) : CGFloat.random(in: 36...52)
            case .normal: return isPlaying
                ? CGFloat.random(in: 30...(46 + CGFloat(waveStage) * 4))
                : CGFloat.random(in: 22...36)
            }
        }()

        let softCap = isPlaying ? (9 + min(waveStage, 2)) : 4
        if bubbles.count >= softCap { return }

        let bubble = GameBubble(
            id: UUID(),
            fruit: fruit,
            kind: prefer,
            size: size,
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
        let originY = shipY - 28
        let coreDmg = shipLevel >= 5 ? 2 : 1
        let sideDmg = 1
        let volley: [(CGFloat, CGFloat, Int)] = {
            switch shipLevel {
            case 0...1:
                return [(0, 0, 1)]
            case 2...3:
                return [(-11, 0, sideDmg), (11, 0, sideDmg)]
            case 4...6:
                return [(-15, 0, sideDmg), (0, 0, coreDmg), (15, 0, sideDmg)]
            case 7...11:
                return [(-18, -24, sideDmg), (-6, 0, coreDmg), (6, 0, coreDmg), (18, 24, sideDmg)]
            default:
                let spread = min(26, 14 + CGFloat(shipLevel - 11))
                return [
                    (-spread, -32, sideDmg),
                    (-spread * 0.4, 0, coreDmg),
                    (0, 0, coreDmg),
                    (spread * 0.4, 0, coreDmg),
                    (spread, 32, sideDmg),
                ]
            }
        }()
        let speed: CGFloat = 430 + CGFloat(min(shipLevel, 24)) * 12
        let hot = shipLevel >= 5
        for (dx, vx, shotDmg) in volley {
            shots.append(
                LaserShot(
                    id: UUID(),
                    position: CGPoint(x: shipX + dx, y: originY),
                    speed: speed,
                    length: shipLevel >= 6 ? 20 : 14,
                    width: shipLevel >= 10 ? 4.2 : (shipLevel >= 6 ? 3.6 : 2.8),
                    vx: vx,
                    damage: shotDmg,
                    glow: hot
                        ? GameTheme.beamHot.opacity(0.9)
                        : GameTheme.beam.opacity(0.88),
                    gradient: LinearGradient(
                        colors: hot
                            ? [Color.white, GameTheme.beamHot, GameTheme.accent.opacity(0.35)]
                            : [Color.white, GameTheme.beam, GameTheme.shipWing.opacity(0.35)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            )
        }
        if shots.count > 18 {
            shots.removeFirst(shots.count - 18)
        }
        playSFX(.shoot)
    }

    private func destroyOrb(_ bubble: GameBubble, fromShot: Bool) {
        emitShatter(from: bubble)
        emitRipple(from: bubble)

        guard isPlaying else {
            playSFX(.pop)
            if hapticsOn {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            }
            spawnBubble(animated: true, prefer: .normal)
            return
        }
        guard fromShot else { return }

        let heavy = bubble.kind == .titan || bubble.kind == .elite
        playSFX(heavy ? .bigPop : .pop)

        brokenTotal += 1
        UserDefaults.standard.set(brokenTotal, forKey: Keys.broken)
        shatterHaptic(heavy: heavy)
        combo += 1
        killsThisRun += 1

        let kindBonus: Int = {
            switch bubble.kind {
            case .normal: return 8
            case .swarm: return 5
            case .zig: return 16
            case .elite: return 40
            case .titan: return 110
            }
        }()
        let xpGain: Int = {
            switch bubble.kind {
            case .normal: return 10
            case .swarm: return 7
            case .zig: return 16
            case .elite: return 32
            case .titan: return 80
            }
        }()
        score += kindBonus + min(combo, 12) * 2
        shipXP += xpGain

        if bubble.kind == .titan {
            spawnFloatText("+西瓜", at: bubble.position, color: bubble.fruit.accent, size: 18)
        } else if bubble.kind == .elite {
            spawnFloatText("菠萝 +\(kindBonus)", at: bubble.position, color: .white, size: 13)
        }

        refreshShipLevel()
        advanceWaveIfNeeded()

        if bubbles.count < 5 + waveStage / 2 {
            spawnBubble(animated: true, prefer: .normal)
        }
    }

    private func advanceWaveIfNeeded() {
        let nextStage: Int = {
            switch killsThisRun {
            case 0..<12: return 0
            case 12..<28: return 1
            case 28..<48: return 2
            case 48..<75: return 3
            default: return 4
            }
        }()
        guard nextStage > waveStage else { return }
        waveStage = nextStage
        let tip: String = {
            switch waveStage {
            case 1: return "新目标：草莓群"
            case 2: return "新目标：游走果"
            case 3: return "新目标：菠萝"
            case 4: return "新目标：大西瓜"
            default: return "压力上升"
            }
        }()
        spawnFloatText(tip, at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.28), color: Color(red: 1.0, green: 0.9, blue: 0.5), size: 15)
        playSFX(.wave)
        if hapticsOn {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
        }
    }

    private func refreshShipLevel() {
        var leveled = false
        while shipXP >= xpToAdvance(from: shipLevel) {
            shipXP -= xpToAdvance(from: shipLevel)
            shipLevel += 1
            leveled = true
        }
        guard leveled else { return }
        spawnFloatText("升级 Lv.\(shipLevel)", at: CGPoint(x: shipX, y: shipY - 50), color: Color(red: 1.0, green: 0.85, blue: 0.35), size: 14)
        playSFX(.levelUp)
        withAnimation(.easeOut(duration: 0.12)) { levelFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { levelFlash = false }
        }
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func spawnFloatText(_ text: String, at point: CGPoint, color: Color, size: CGFloat) {
        if floatTexts.count > 5 {
            floatTexts.removeFirst(floatTexts.count - 5)
        }
        let id = UUID()
        floatTexts.append(FloatText(id: id, text: text, position: point, color: color, fontSize: size, opacity: 1))
        withAnimation(.easeOut(duration: 0.7)) {
            if let i = floatTexts.firstIndex(where: { $0.id == id }) {
                floatTexts[i].position.y -= 36
                floatTexts[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            floatTexts.removeAll { $0.id == id }
        }
    }

    private func emitHitSpark(at point: CGPoint, color: Color) {
        if ripples.count > 6 { return }
        let id = UUID()
        ripples.append(PopRipple(id: id, position: point, color: color, size: 10, opacity: 0.55, lineWidth: 1.2))
        withAnimation(.easeOut(duration: 0.2)) {
            if let i = ripples.firstIndex(where: { $0.id == id }) {
                ripples[i].size = 22
                ripples[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            ripples.removeAll { $0.id == id }
        }
    }

    private func emitRipple(from bubble: GameBubble) {
        // Skip most ripples for normals — shatter is enough visual feedback.
        if bubble.kind == .normal || bubble.kind == .swarm { return }
        if ripples.count > 6 { return }
        let id = UUID()
        ripples.append(
            PopRipple(
                id: id,
                position: bubble.position,
                color: bubble.fruit.accent,
                size: bubble.size * 0.3,
                opacity: 0.75,
                lineWidth: bubble.kind == .titan ? 2.5 : 1.6
            )
        )
        withAnimation(.easeOut(duration: 0.35)) {
            if let i = ripples.firstIndex(where: { $0.id == id }) {
                ripples[i].size = bubble.size * (bubble.kind == .titan ? 2.2 : 1.8)
                ripples[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            ripples.removeAll { $0.id == id }
        }
    }

    private func emitShatter(from bubble: GameBubble) {
        let count = bubble.kind == .titan ? 6 : (bubble.kind == .elite ? 5 : 3)
        if shards.count > 20 {
            shards.removeFirst(shards.count - 20)
        }
        var newShards: [ShatterShard] = []
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let dist = Double.random(in: 20...(bubble.kind == .titan ? 70 : 48))
            let id = UUID()
            let end = CGPoint(
                x: bubble.position.x + CGFloat(cos(angle) * dist),
                y: bubble.position.y + CGFloat(sin(angle) * dist)
            )
            newShards.append(
                ShatterShard(
                    id: id,
                    color: bubble.fruit.accent,
                    position: bubble.position,
                    width: CGFloat.random(in: 2...5),
                    height: CGFloat.random(in: 6...14),
                    rotation: Double.random(in: 0...360),
                    opacity: 1,
                    blur: 0
                )
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeOut(duration: 0.28)) {
                    if let i = shards.firstIndex(where: { $0.id == id }) {
                        shards[i].position = end
                        shards[i].opacity = 0
                        shards[i].rotation += Double.random(in: 40...120)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                shards.removeAll { $0.id == id }
            }
        }
        shards.append(contentsOf: newShards)
    }

    private func shatterHaptic(heavy: Bool) {
        guard hapticsOn else { return }
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        let impact = UIImpactFeedbackGenerator(style: heavy ? .heavy : .medium)
        rigid.prepare()
        impact.prepare()
        rigid.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            impact.impactOccurred(intensity: heavy ? 1.0 : 0.8)
        }
    }
}

// MARK: - Models

private enum FruitKind: CaseIterable {
    case apple, greenApple, banana, orange, grape, lemon, strawberry, cherry, peach, kiwi, watermelon, pineapple

    var emoji: String {
        switch self {
        case .apple: return "🍎"
        case .greenApple: return "🍏"
        case .banana: return "🍌"
        case .orange: return "🍊"
        case .grape: return "🍇"
        case .lemon: return "🍋"
        case .strawberry: return "🍓"
        case .cherry: return "🍒"
        case .peach: return "🍑"
        case .kiwi: return "🥝"
        case .watermelon: return "🍉"
        case .pineapple: return "🍍"
        }
    }

    var name: String {
        switch self {
        case .apple: return "苹果"
        case .greenApple: return "青苹果"
        case .banana: return "香蕉"
        case .orange: return "橙子"
        case .grape: return "葡萄"
        case .lemon: return "柠檬"
        case .strawberry: return "草莓"
        case .cherry: return "樱桃"
        case .peach: return "桃子"
        case .kiwi: return "猕猴桃"
        case .watermelon: return "西瓜"
        case .pineapple: return "菠萝"
        }
    }

    var accent: Color {
        switch self {
        case .apple: return Color(red: 0.95, green: 0.28, blue: 0.32)
        case .greenApple: return Color(red: 0.45, green: 0.82, blue: 0.38)
        case .banana: return Color(red: 1.0, green: 0.82, blue: 0.22)
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.18)
        case .grape: return Color(red: 0.58, green: 0.32, blue: 0.88)
        case .lemon: return Color(red: 1.0, green: 0.88, blue: 0.28)
        case .strawberry: return Color(red: 0.98, green: 0.32, blue: 0.42)
        case .cherry: return Color(red: 0.92, green: 0.18, blue: 0.32)
        case .peach: return Color(red: 1.0, green: 0.62, blue: 0.48)
        case .kiwi: return Color(red: 0.55, green: 0.72, blue: 0.28)
        case .watermelon: return Color(red: 0.28, green: 0.78, blue: 0.42)
        case .pineapple: return Color(red: 1.0, green: 0.78, blue: 0.22)
        }
    }

    static func random(for kind: OrbKind) -> FruitKind {
        switch kind {
        case .normal:
            return [.apple, .greenApple, .banana, .orange, .peach, .kiwi, .lemon].randomElement()!
        case .swarm:
            return [.strawberry, .cherry, .grape].randomElement()!
        case .elite:
            return .pineapple
        case .zig:
            return [.cherry, .grape, .lemon].randomElement()!
        case .titan:
            return .watermelon
        }
    }
}

private enum OrbKind {
    case normal, swarm, elite, zig, titan
}

private struct GameBubble: Identifiable {
    let id: UUID
    let fruit: FruitKind
    let kind: OrbKind
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
}

private struct PopRipple: Identifiable {
    let id: UUID
    let position: CGPoint
    let color: Color
    var size: CGFloat
    var opacity: Double
    var lineWidth: CGFloat
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
}
