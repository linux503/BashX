import SwiftUI
import UIKit

/// Camouflage space-shooter with levels, titans, and upgrading ship.
/// Unlock: tap the tip card above Start 5 times.
struct DisguiseGalleryView: View {
    var onUnlocked: () -> Void

    @State private var bubbles: [GameBubble] = []
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
    private let maxLives = 5

    private let colorfulPalette: [Color] = [
        Color(red: 0.98, green: 0.28, blue: 0.40),
        Color(red: 0.98, green: 0.55, blue: 0.16),
        Color(red: 1.0, green: 0.86, blue: 0.18),
        Color(red: 0.22, green: 0.90, blue: 0.55),
        Color(red: 0.20, green: 0.72, blue: 0.98),
        Color(red: 0.58, green: 0.38, blue: 0.98),
        Color(red: 0.98, green: 0.38, blue: 0.78),
        Color(red: 0.45, green: 0.92, blue: 0.95),
    ]

    private enum Keys {
        static let broken = "disguise.colorPop.brokenTotal"
        static let high = "disguise.colorPop.high"
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
        case 0: return "原型机"
        case 1: return "侦察机"
        case 2: return "突击舰"
        case 3: return "双联炮"
        case 4: return "星际驱逐"
        case 5...9: return "战列舰"
        case 10...19: return "星际要塞"
        default: return "超维旗舰"
        }
    }

    /// Visual size soft-cap so the ship stays on screen at high levels.
    private var shipVisualLevel: CGFloat {
        CGFloat(min(shipLevel, 15))
    }

    var body: some View {
        ZStack {
            spaceBackdrop.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    ForEach(stars) { star in
                        Circle()
                            .fill(Color.white.opacity(star.opacity))
                            .frame(width: star.size, height: star.size)
                            .position(star.position)
                            .blur(radius: star.size > 2.2 ? 0.5 : 0)
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
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.95), shard.color],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: shard.width, height: shard.height)
                            .rotationEffect(.degrees(shard.rotation))
                            .opacity(shard.opacity)
                            .position(shard.position)
                            .blur(radius: shard.blur)
                            .allowsHitTesting(false)
                    }

                    ForEach(bubbles) { bubble in
                        orbView(bubble)
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
                        Color.white.opacity(0.12).ignoresSafeArea().allowsHitTesting(false)
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
                    if stars.count < 40 { seedStars(in: newSize) }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if !isPlaying {
                    homeCard
                        .padding(.bottom, 10)
                        .onTapGesture { handleUnlockTap() }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                bottomBar
                    .padding(.bottom, isPlaying ? 52 : 40)
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isPlaying)
            }
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
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                startPulse = true
            }
        }
    }

    private func updatePlayfield(_ size: CGSize) {
        playSize = size
        let insets = keyWindowSafeInsets()
        playTop = insets.top + 92
        playBottom = max(insets.bottom, 16) + (isPlaying ? 96 : 108)
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

    private var spaceBackdrop: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Cinematic deep space — indigo → violet → teal
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.05, blue: 0.14),
                        Color(
                            hue: (0.68 + 0.04 * sin(t * 0.08)).truncatingRemainder(dividingBy: 1),
                            saturation: 0.62,
                            brightness: 0.16
                        ),
                        Color(
                            hue: (0.78 + 0.05 * cos(t * 0.07)).truncatingRemainder(dividingBy: 1),
                            saturation: 0.48,
                            brightness: 0.12
                        ),
                        Color(red: 0.03, green: 0.08, blue: 0.12),
                    ],
                    startPoint: UnitPoint(x: 0.2 + 0.1 * sin(t * 0.04), y: 0),
                    endPoint: UnitPoint(x: 0.8 + 0.08 * cos(t * 0.05), y: 1)
                )

                // Soft aurora ribbons
                AngularGradient(
                    colors: [
                        Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.22),
                        Color(red: 0.55, green: 0.28, blue: 0.95).opacity(0.18),
                        Color(red: 0.15, green: 0.82, blue: 0.78).opacity(0.14),
                        Color(red: 0.95, green: 0.45, blue: 0.70).opacity(0.10),
                        Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.22),
                    ],
                    center: UnitPoint(
                        x: 0.48 + 0.18 * cos(t * 0.12),
                        y: 0.32 + 0.14 * sin(t * 0.10)
                    ),
                    angle: .degrees(t * 8)
                )
                .blur(radius: 48)
                .opacity(0.9)

                // Horizon glow
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color(red: 0.25, green: 0.55, blue: 0.95).opacity(0.12),
                        Color(red: 0.55, green: 0.25, blue: 0.85).opacity(0.08),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 220)
                .offset(y: 180 + 30 * sin(t * 0.09))
                .blur(radius: 24)

                // Moving light wells
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.32),
                                Color(red: 0.30, green: 0.45, blue: 0.95).opacity(0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 240
                        )
                    )
                    .frame(width: 480, height: 480)
                    .offset(x: 100 * cos(t * 0.11), y: -60 + 60 * sin(t * 0.09))
                    .blur(radius: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.90, green: 0.40, blue: 0.95).opacity(0.20),
                                Color(red: 0.40, green: 0.20, blue: 0.70).opacity(0.06),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 190
                        )
                    )
                    .frame(width: 380, height: 380)
                    .offset(x: -110 * sin(t * 0.10), y: 140 + 45 * cos(t * 0.08))
                    .blur(radius: 14)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.20, green: 0.90, blue: 0.80).opacity(0.12),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 140
                        )
                    )
                    .frame(width: 280, height: 280)
                    .offset(x: 40 * sin(t * 0.15), y: -160 + 40 * cos(t * 0.12))
                    .blur(radius: 10)

                // Film vignette
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.42)],
                    center: .center,
                    startRadius: 100,
                    endRadius: 560
                )
            }
        }
    }

    private func orbView(_ bubble: GameBubble) -> some View {
        let pulse = 1 + 0.035 * sin(bubble.phase)
        let hpRatio = CGFloat(bubble.hp) / CGFloat(max(1, bubble.maxHp))
        let rim = [
            Color.white.opacity(0.85),
            bubble.color.opacity(0.9),
            Color.white.opacity(0.15),
        ]
        return ZStack {
            // Outer chromatic bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            bubble.color.opacity(0.55),
                            bubble.color.opacity(0.18),
                            bubble.color.opacity(0.04),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: bubble.size * 1.05
                    )
                )
                .frame(width: bubble.size * 1.7, height: bubble.size * 1.7)
                .blur(radius: bubble.kind == .titan ? 14 : 9)

            // Soft secondary halo
            Circle()
                .fill(bubble.color.opacity(0.18))
                .frame(width: bubble.size * 1.25, height: bubble.size * 1.25)
                .blur(radius: 6)

            if bubble.kind == .titan || bubble.kind == .elite {
                ForEach(0..<(bubble.kind == .titan ? 3 : 1), id: \.self) { ring in
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: rim + [rim[0]],
                                center: .center
                            ),
                            style: StrokeStyle(
                                lineWidth: bubble.kind == .titan ? 2.0 : 1.4,
                                dash: bubble.kind == .titan ? [5, 5] : []
                            )
                        )
                        .frame(
                            width: bubble.size * (1.2 + CGFloat(ring) * 0.18),
                            height: bubble.size * (1.2 + CGFloat(ring) * 0.18)
                        )
                        .rotationEffect(.degrees(bubble.phase * (16 + Double(ring) * 12) * (ring % 2 == 0 ? 1 : -1)))
                        .opacity(0.55 - Double(ring) * 0.1)
                }
            }

            // Glass core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            bubble.color.opacity(0.95),
                            bubble.color.opacity(0.72),
                            bubble.color.opacity(0.38),
                            bubble.color.opacity(0.18),
                        ],
                        center: UnitPoint(x: 0.28, y: 0.24),
                        startRadius: 0.2,
                        endRadius: bubble.size * 0.72
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.9), bubble.color.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: bubble.kind == .titan ? 2.2 : 1.2
                        )
                }
                .overlay {
                    // Inner glass rim
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        .padding(3)
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.95), .white.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: bubble.size * 0.36, height: bubble.size * 0.18)
                        .offset(x: bubble.size * 0.12, y: bubble.size * 0.12)
                        .blur(radius: 0.3)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: bubble.size * 0.12, height: bubble.size * 0.12)
                        .offset(x: -bubble.size * 0.18, y: -bubble.size * 0.2)
                        .blur(radius: 0.5)
                }
                .shadow(color: bubble.color.opacity(0.72), radius: bubble.kind == .titan ? 18 : 11, y: 3)
                .frame(width: bubble.size, height: bubble.size)

            if bubble.maxHp > 1 {
                Circle()
                    .trim(from: 0, to: hpRatio)
                    .stroke(
                        AngularGradient(
                            colors: [.white, bubble.color, Color.white.opacity(0.35)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: bubble.kind == .titan ? 3.2 : 2.0, lineCap: .round)
                    )
                    .frame(width: bubble.size * 0.9, height: bubble.size * 0.9)
                    .rotationEffect(.degrees(-90))
            }

            if bubble.kind == .titan {
                Image(systemName: "seal.fill")
                    .font(.system(size: bubble.size * 0.2, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.85), bubble.color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .white.opacity(0.4), radius: 4)
            }
        }
        .frame(width: bubble.size * 1.6, height: bubble.size * 1.6)
        .scaleEffect(bubble.scale * pulse)
    }

    private var shipView: some View {
        let accent: Color = {
            let hues: [Double] = [0.55, 0.48, 0.62, 0.78, 0.12, 0.08]
            let h = hues[min(shipLevel, hues.count - 1)]
            if shipLevel >= 10 {
                return Color(hue: (0.12 + Double(shipLevel % 7) * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1.0)
            }
            return Color(hue: h, saturation: 0.75, brightness: 0.98)
        }()
        let metal = Color(red: 0.72, green: 0.8, blue: 0.92)
        let scale: CGFloat = 0.9 + shipVisualLevel * 0.035

        return ZStack {
            // Engine plume
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.85 - Double(i) * 0.2),
                                accent.opacity(0),
                            ],
                            center: .top,
                            startRadius: 1,
                            endRadius: 20
                        )
                    )
                    .frame(
                        width: CGFloat(8 + i * 4) + 3 * sin(thrustPhase + CGFloat(i)),
                        height: CGFloat(18 + i * 8) + 6 * sin(thrustPhase * 1.3 + CGFloat(i))
                    )
                    .offset(y: 28 + CGFloat(i) * 4)
                    .blur(radius: CGFloat(1 + i))
            }

            // Shadow plate
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: 44, height: 12)
                .offset(y: 26)
                .blur(radius: 4)

            // Wings
            Path { path in
                let wing = 18 + shipVisualLevel * 2.2
                path.move(to: CGPoint(x: 32, y: 16))
                path.addLine(to: CGPoint(x: 32 - wing, y: 32))
                path.addLine(to: CGPoint(x: 32 - wing * 0.35, y: 26))
                path.addLine(to: CGPoint(x: 28, y: 20))
                path.closeSubpath()
                path.move(to: CGPoint(x: 32, y: 16))
                path.addLine(to: CGPoint(x: 32 + wing, y: 32))
                path.addLine(to: CGPoint(x: 32 + wing * 0.35, y: 26))
                path.addLine(to: CGPoint(x: 36, y: 20))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [metal, accent.opacity(0.85), Color(red: 0.18, green: 0.28, blue: 0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Path { path in
                    let wing = 18 + shipVisualLevel * 2.2
                    path.move(to: CGPoint(x: 32, y: 16))
                    path.addLine(to: CGPoint(x: 32 - wing, y: 32))
                    path.move(to: CGPoint(x: 32, y: 16))
                    path.addLine(to: CGPoint(x: 32 + wing, y: 32))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
            )
            .frame(width: 60 + shipVisualLevel * 3.5, height: 42)
            .shadow(color: accent.opacity(0.45), radius: 8, y: 2)

            // Side cannons
            if shipLevel >= 3 {
                ForEach([-1, 1], id: \.self) { side in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(colors: [accent, metal], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 7, height: 18)
                    }
                    .offset(x: CGFloat(side) * (18 + shipVisualLevel * 1.1), y: 2)
                    .shadow(color: accent.opacity(0.8), radius: 5)
                }
            }

            // Hull
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            metal,
                            accent.opacity(0.85),
                            Color(red: 0.12, green: 0.22, blue: 0.48),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 14 + shipVisualLevel * 0.7, height: 32 + shipVisualLevel * 1.1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), accent.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .overlay(alignment: .center) {
                    Capsule()
                        .fill(accent.opacity(0.55))
                        .frame(width: 3, height: 16)
                        .offset(y: 4)
                }
                .shadow(color: accent.opacity(0.65), radius: 14, y: 2)

            // Cockpit canopy
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            accent.opacity(0.75),
                            Color(red: 0.2, green: 0.45, blue: 0.9).opacity(0.8),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 8 + shipVisualLevel * 0.25, height: 11)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.6))
                .offset(y: -10)
                .shadow(color: accent.opacity(0.6), radius: 4)

            if shipLevel >= 5 {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.92, blue: 0.45))
                    .offset(y: 4)
                    .shadow(color: Color.yellow.opacity(0.8), radius: 4)
            }
        }
        .frame(width: 78, height: 70)
        .scaleEffect(scale)
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("色点消消乐")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    Text(isPlaying ? "守住防线 · 优先快球" : "拖动飞船射击")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer(minLength: 8)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
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
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var scoreChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.45, green: 0.92, blue: 1.0))
            VStack(alignment: .leading, spacing: 0) {
                Text("分数")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                Text("\(score)")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(chipBackground(tint: Color(red: 0.35, green: 0.85, blue: 1.0)))
    }

    private var levelChip: some View {
        let need = xpToAdvance(from: shipLevel)
        let progress = need > 0 ? min(1, CGFloat(shipXP) / CGFloat(need)) : 0
        return HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Lv.\(shipLevel)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.42))
                    Text(shipTitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.78, blue: 0.28),
                                        Color(red: 1.0, green: 0.55, blue: 0.25),
                                    ],
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
        .background(chipBackground(tint: Color(red: 1.0, green: 0.78, blue: 0.35)))
    }

    private var livesChip: some View {
        HStack(spacing: 3) {
            ForEach(0..<maxLives, id: \.self) { i in
                Circle()
                    .fill(i < lives ? Color(red: 1.0, green: 0.42, blue: 0.48) : Color.white.opacity(0.15))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(i < lives ? 0.35 : 0.12), lineWidth: 0.6)
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(chipBackground(tint: Color(red: 1.0, green: 0.42, blue: 0.48)))
        .accessibilityLabel("防线 \(lives)")
    }

    private var comboChip: some View {
        Text("×\(combo)")
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(red: 0.9, green: 0.75, blue: 1.0))
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(chipBackground(tint: Color(red: 0.85, green: 0.7, blue: 1.0)))
    }

    private func chipBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
            )
    }

    private var homeCard: some View {
        VStack(spacing: 3) {
            Text("星际护航")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text("5 点防线 · 优先清快球")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6)
                )
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
                        .fill(Color(red: 0.45, green: 0.78, blue: 1.0).opacity(startPulse ? 0.28 : 0.12))
                        .blur(radius: 10)
                        .scaleEffect(startPulse ? 1.06 : 1.0)
                        .allowsHitTesting(false)
                }

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isPlaying
                                ? [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.07),
                                ]
                                : [
                                    Color(red: 0.38, green: 0.92, blue: 1.0),
                                    Color(red: 0.42, green: 0.58, blue: 1.0),
                                    Color(red: 0.72, green: 0.38, blue: 0.95),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isPlaying ? 0.28 : 0.55),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: isPlaying
                            ? Color.black.opacity(0.22)
                            : Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.32),
                        radius: isPlaying ? 6 : 10,
                        y: isPlaying ? 2 : 4
                    )

                HStack(spacing: 6) {
                    Image(systemName: isPlaying ? "stop.fill" : "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(isPlaying ? "结束" : "开始游戏")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: isPlaying ? 96 : 128, height: 36)
            .compositingGroup()
        }
        .buttonStyle(.plain)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("破碎震感", isOn: $hapticsOn)
                } header: {
                    Text("手感")
                }

                Section {
                    LabeledContent("飞船等级", value: "Lv.\(shipLevel)")
                    LabeledContent("升级经验", value: "\(shipXP)/\(xpToAdvance(from: shipLevel))")
                    LabeledContent("本局阶段", value: "第 \(waveStage + 1) 波")
                    LabeledContent("防线", value: "\(lives)/\(maxLives)")
                    LabeledContent("本局分数", value: "\(score)")
                    LabeledContent("累计击破", value: "\(brokenTotal)")
                    LabeledContent("历史最高", value: "\(highScore)")
                } header: {
                    Text("战绩")
                } footer: {
                    Text("等级靠经验慢慢涨，无上限。漏掉色核会掉防线；防线归零本局结束。新种类会随击破逐步出现。")
                }

                Section {
                    Button {
                        shipLevel = 0
                        shipXP = 0
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("重置飞船等级为 0", systemImage: "arrow.counterclockwise.circle")
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
            .navigationTitle("游戏设置")
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

    private func startMotionLoop() {
        motionTask?.cancel()
        motionTask = Task { @MainActor in
            let dt: CGFloat = 1.0 / 30.0
            while !Task.isCancelled {
                tickMotion(dt: dt)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func tickMotion(dt: CGFloat) {
        guard playSize.width > 0 else { return }
        thrustPhase += dt * (12 + CGFloat(shipLevel) * 2)

        for i in stars.indices {
            stars[i].position.y += stars[i].speed * dt * (isPlaying ? 1.0 + CGFloat(difficulty) * 0.08 : 0.7)
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
            // Zig enemies weave while falling
            if bubbles[i].kind == .zig {
                bubbles[i].vx = sin(bubbles[i].phase * 1.8) * bubbles[i].weaveAmp
            }
            bubbles[i].position.x += bubbles[i].vx * dt
            // Always fall downward from top
            bubbles[i].position.y += abs(bubbles[i].vy) * dt

            let r = bubbles[i].size * 0.5
            if bubbles[i].position.x - r < minX {
                bubbles[i].position.x = minX + r
                bubbles[i].vx = abs(bubbles[i].vx)
            } else if bubbles[i].position.x + r > maxX {
                bubbles[i].position.x = maxX - r
                bubbles[i].vx = -abs(bubbles[i].vx)
            }

            if bubbles[i].kind != .zig {
                // Mild horizontal drift only — never reverse fall
                bubbles[i].vx += CGFloat.random(in: -10...10) * dt
                bubbles[i].vx = max(-50, min(50, bubbles[i].vx))
            }

            // Clamp fall speed by kind
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
                bubbles[bIdx].scale = 1.12
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                    if bIdx < bubbles.count { bubbles[bIdx].scale = 1 }
                }
                emitHitSpark(at: bubbles[bIdx].position, color: bubbles[bIdx].color)

                if bubbles[bIdx].hp <= 0 {
                    let dead = bubbles.remove(at: bIdx)
                    destroyOrb(dead, fromShot: true)
                } else if isPlaying, hapticsOn {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                }
            }
        }
        if !removeShots.isEmpty {
            shots.removeAll { removeShots.contains($0.id) }
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
        for _ in 0..<5 {
            spawnBubble(animated: true, prefer: .normal)
        }
        spawnFloatText("防守开始", at: CGPoint(x: playSize.width * 0.5, y: shipY - 80), color: .white, size: 15)

        spawnTask = Task { @MainActor in
            while !Task.isCancelled {
                spawnForDifficulty()
                // Slower early waves; pressure rises with stage, not ship power
                let base = max(340, 920 - waveStage * 70 - difficulty * 18)
                try? await Task.sleep(nanoseconds: UInt64(base) * 1_000_000)
                if waveStage >= 4, Int.random(in: 0...4) == 0 {
                    spawnForDifficulty()
                }
                if bubbles.count > 11 + waveStage {
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
        let ns = 280_000_000 - min(shipLevel, 22) * 8_000_000
        return UInt64(max(110_000_000, ns))
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
        spawnFloatText("漏防 −1", at: CGPoint(x: shipX, y: shipY - 56), color: Color(red: 1.0, green: 0.45, blue: 0.45), size: 14)
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
        spawnFloatText("防线失守", at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.42), color: Color(red: 1.0, green: 0.4, blue: 0.45), size: 20)
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
        stars = (0..<64).map { _ in
            StarDust(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                size: CGFloat.random(in: 1.0...2.8),
                opacity: Double.random(in: 0.22...0.85),
                speed: CGFloat.random(in: 16...80)
            )
        }
    }

    private func seedIdleBubbles() {
        bubbles.removeAll()
        shots.removeAll()
        for _ in 0..<8 {
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
        let color = colorfulPalette.randomElement()!

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

        let bubble = GameBubble(
            id: UUID(),
            color: color,
            kind: prefer,
            size: size,
            position: CGPoint(x: spawnX, y: spawnY),
            scale: animated ? 0.12 : 1,
            vx: prefer == .zig ? weave * 0.4 : CGFloat.random(in: -18...18),
            vy: fallSpeed,
            phase: CGFloat.random(in: 0...(2 * .pi)),
            pulseSpeed: prefer == .titan ? CGFloat.random(in: 0.8...1.4) : CGFloat.random(in: 1.4...2.8),
            hp: hp,
            maxHp: hp,
            weaveAmp: weave
        )
        bubbles.append(bubble)
        if animated {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.64)) {
                if let i = bubbles.firstIndex(where: { $0.id == bubble.id }) {
                    bubbles[i].scale = 1
                }
            }
        }
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
                        ? Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.9)
                        : Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.85),
                    gradient: LinearGradient(
                        colors: hot
                            ? [Color.white, Color(red: 1.0, green: 0.85, blue: 0.35), Color.orange.opacity(0.2)]
                            : [Color.white, Color(red: 0.35, green: 0.85, blue: 1.0), Color.blue.opacity(0.15)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            )
        }
        if shots.count > 40 {
            shots.removeFirst(shots.count - 40)
        }
    }

    private func destroyOrb(_ bubble: GameBubble, fromShot: Bool) {
        emitShatter(from: bubble)
        emitRipple(from: bubble)

        guard isPlaying else {
            if hapticsOn {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            }
            spawnBubble(animated: true, prefer: .normal)
            return
        }
        guard fromShot else { return }

        brokenTotal += 1
        UserDefaults.standard.set(brokenTotal, forKey: Keys.broken)
        shatterHaptic(heavy: bubble.kind == .titan || bubble.kind == .elite)
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
            spawnFloatText("+泰坦", at: bubble.position, color: bubble.color, size: 18)
        } else if bubble.kind == .elite {
            spawnFloatText("坚核 +\(kindBonus)", at: bubble.position, color: .white, size: 13)
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
            case 1: return "新目标：群核"
            case 2: return "新目标：游走核"
            case 3: return "新目标：坚核"
            case 4: return "新目标：泰坦"
            default: return "压力上升"
            }
        }()
        spawnFloatText(tip, at: CGPoint(x: playSize.width * 0.5, y: playSize.height * 0.28), color: Color(red: 1.0, green: 0.9, blue: 0.5), size: 15)
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
        withAnimation(.easeOut(duration: 0.12)) { levelFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { levelFlash = false }
        }
        if hapticsOn {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func spawnFloatText(_ text: String, at point: CGPoint, color: Color, size: CGFloat) {
        let id = UUID()
        floatTexts.append(FloatText(id: id, text: text, position: point, color: color, fontSize: size, opacity: 1))
        withAnimation(.easeOut(duration: 0.85)) {
            if let i = floatTexts.firstIndex(where: { $0.id == id }) {
                floatTexts[i].position.y -= 42
                floatTexts[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            floatTexts.removeAll { $0.id == id }
        }
    }

    private func emitHitSpark(at point: CGPoint, color: Color) {
        let id = UUID()
        ripples.append(PopRipple(id: id, position: point, color: color, size: 10, opacity: 0.7, lineWidth: 1.5))
        withAnimation(.easeOut(duration: 0.25)) {
            if let i = ripples.firstIndex(where: { $0.id == id }) {
                ripples[i].size = 28
                ripples[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            ripples.removeAll { $0.id == id }
        }
    }

    private func emitRipple(from bubble: GameBubble) {
        let id = UUID()
        ripples.append(
            PopRipple(
                id: id,
                position: bubble.position,
                color: bubble.color,
                size: bubble.size * 0.3,
                opacity: 0.9,
                lineWidth: bubble.kind == .titan ? 3 : 2
            )
        )
        withAnimation(.easeOut(duration: 0.45)) {
            if let i = ripples.firstIndex(where: { $0.id == id }) {
                ripples[i].size = bubble.size * (bubble.kind == .titan ? 3.0 : 2.2)
                ripples[i].opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ripples.removeAll { $0.id == id }
        }
    }

    private func emitShatter(from bubble: GameBubble) {
        let count = bubble.kind == .titan ? Int.random(in: 18...26) : Int.random(in: 10...16)
        var newShards: [ShatterShard] = []
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let dist = Double.random(in: 28...(bubble.kind == .titan ? 140 : 95))
            let id = UUID()
            newShards.append(
                ShatterShard(
                    id: id,
                    color: [bubble.color, .white.opacity(0.95)].randomElement()!,
                    position: bubble.position,
                    width: CGFloat.random(in: 2.5...9),
                    height: CGFloat.random(in: 8...24),
                    rotation: Double.random(in: 0...360),
                    opacity: 1,
                    blur: 0
                )
            )
            let end = CGPoint(
                x: bubble.position.x + CGFloat(cos(angle) * dist),
                y: bubble.position.y + CGFloat(sin(angle) * dist)
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeOut(duration: 0.42)) {
                    if let i = shards.firstIndex(where: { $0.id == id }) {
                        shards[i].position = end
                        shards[i].opacity = 0
                        shards[i].rotation += Double.random(in: 80...220)
                        shards[i].blur = 1
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

private enum OrbKind {
    case normal, swarm, elite, zig, titan
}

private struct GameBubble: Identifiable {
    let id: UUID
    let color: Color
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
}

private struct FloatText: Identifiable {
    let id: UUID
    let text: String
    var position: CGPoint
    let color: Color
    let fontSize: CGFloat
    var opacity: Double
}
