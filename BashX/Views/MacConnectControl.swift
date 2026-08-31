import SwiftUI

/// Mac minimal home connect control — mirrors iOS `IOSConnectControl` look & motion.
struct MacConnectControl: View {
    let isConnected: Bool
    let isBusy: Bool
    let appearance: AppAppearance
    var language: AppLanguage = .system
    let action: () -> Void

    @State private var pulse = false
    @State private var rotation: Double = 0
    @State private var pressScale: CGFloat = 1
    @State private var orbitAngle: Double = 0
    @State private var radarSweep: Double = 0
    @State private var breath = false

    private var lang: AppLanguage { language }

    var body: some View {
        Button(action: tapConnect) {
            connectArtwork
                .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(isConnected ? L10n.t("mac.minimal.disconnect", lang) : L10n.t("mac.minimal.connect", lang))
        .onAppear { syncAnimations() }
        .onChange(of: isConnected) { _ in syncAnimations() }
        .onChange(of: isBusy) { busy in
            if busy { startSpin() } else { rotation = 0 }
            syncAnimations()
        }
    }

    private var connectArtwork: some View {
        ZStack {
            ambientGlow
            idleOrbits
            connectedOrbits
            mainRing
            connectingArc
            connectedSatellites
            centerDisc
            centerContent
        }
        .frame(width: 220, height: 220)
        .contentShape(Circle())
    }

    private var ambientGlow: some View {
        Circle()
            .fill(centerShadow.opacity(isConnected ? 0.32 : (breath ? 0.18 : 0.10)))
            .frame(width: 210, height: 210)
            .blur(radius: 28)
            .scaleEffect(breath ? 1.12 : 0.96)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var idleOrbits: some View {
        if !isConnected {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(idleRingGradient, lineWidth: 1.1)
                    .frame(width: 158 + CGFloat(i) * 14, height: 158 + CGFloat(i) * 14)
                    .rotationEffect(.degrees(orbitAngle * (i == 0 ? 1 : -0.8)))
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var idleRingGradient: AngularGradient {
        AngularGradient(
            colors: [
                centerShadow.opacity(0),
                centerShadow.opacity(0.35),
                BashXTheme.accent(for: appearance).opacity(0.22),
                centerShadow.opacity(0),
            ],
            center: .center
        )
    }

    @ViewBuilder
    private var connectedOrbits: some View {
        if isConnected {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(
                        BashXTheme.good(for: appearance).opacity(0.18 - Double(i) * 0.04),
                        style: StrokeStyle(lineWidth: 1.1, dash: [4, 6])
                    )
                    .frame(width: 150 + CGFloat(i) * 16, height: 150 + CGFloat(i) * 16)
                    .rotationEffect(.degrees(orbitAngle + Double(i) * 24))
                    .opacity(pulse ? 0.85 : 0.45)
                    .allowsHitTesting(false)
            }
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(radarGradient, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                .frame(width: 176, height: 176)
                .rotationEffect(.degrees(radarSweep))
                .allowsHitTesting(false)
            Circle()
                .strokeBorder(BashXTheme.good(for: appearance).opacity(0.40), lineWidth: 2)
                .frame(width: 184, height: 184)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .opacity(pulse ? 0.2 : 0.75)
                .allowsHitTesting(false)
        }
    }

    private var radarGradient: AngularGradient {
        let good = BashXTheme.good(for: appearance)
        return AngularGradient(
            colors: [good.opacity(0), good.opacity(0.55), good.opacity(0)],
            center: .center
        )
    }

    private var mainRing: some View {
        Circle()
            .strokeBorder(ringGradient, lineWidth: 3.2)
            .frame(width: 164, height: 164)
            .opacity(0.92)
            .shadow(
                color: centerShadow.opacity(isConnected ? 0.32 : 0.12),
                radius: isConnected ? 10 : 4
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var connectingArc: some View {
        if isBusy {
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(BashXTheme.warn.opacity(0.55), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 176, height: 176)
                .rotationEffect(.degrees(rotation))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var connectedSatellites: some View {
        if isConnected {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(BashXTheme.good(for: appearance))
                    .frame(width: 5, height: 5)
                    .shadow(color: BashXTheme.good(for: appearance).opacity(0.8), radius: 3)
                    .offset(y: -82)
                    .rotationEffect(.degrees(orbitAngle + Double(i) * 90))
                    .allowsHitTesting(false)
            }
        }
    }

    private var centerDisc: some View {
        Circle()
            .fill(centerGradient)
            .frame(width: 132, height: 132)
            .scaleEffect(breath && isConnected ? 1.03 : 1)
            .shadow(color: centerShadow.opacity(0.42), radius: 18, y: 10)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .overlay {
                if isConnected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .padding(9)
                }
            }
            .allowsHitTesting(false)
    }

    private var centerContent: some View {
        VStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else {
                Image(systemName: isConnected ? "checkmark.shield.fill" : "power")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(breath && isConnected ? 1.05 : 1)
            }
            Text(centerLabel)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private func tapConnect() {
        guard !isBusy else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pressScale = 0.94 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressScale = 1 }
        }
        action()
    }

    private func syncAnimations() {
        if isBusy { startSpin() }
        breath = false
        pulse = false
        withAnimation(.easeInOut(duration: isConnected ? 1.9 : 2.8).repeatForever(autoreverses: true)) {
            breath = true
            if isConnected { pulse = true }
        }
        withAnimation(.linear(duration: isConnected ? 10 : 16).repeatForever(autoreverses: false)) {
            orbitAngle = 360
        }
        if isConnected {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                radarSweep = 360
            }
        } else {
            radarSweep = 0
        }
    }

    private func startSpin() {
        rotation = 0
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private var ringGradient: LinearGradient {
        if isConnected {
            return LinearGradient(
                colors: [BashXTheme.good(for: appearance), BashXTheme.good(for: appearance).opacity(0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        if isBusy {
            return LinearGradient(
                colors: [BashXTheme.warn, BashXTheme.warn.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                BashXTheme.accent(for: appearance),
                BashXTheme.accent(for: appearance).opacity(0.55),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var centerGradient: LinearGradient {
        if isConnected {
            return LinearGradient(
                colors: [Color(red: 0.22, green: 0.88, blue: 0.52), Color(red: 0.08, green: 0.62, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        if isBusy {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.78, blue: 0.32), Color(red: 0.92, green: 0.58, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                BashXTheme.accent(for: appearance),
                Color(red: 0.12, green: 0.45, blue: 0.92),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var centerShadow: Color {
        if isConnected { return BashXTheme.good(for: appearance) }
        if isBusy { return BashXTheme.warn }
        return BashXTheme.accent(for: appearance)
    }

    private var centerLabel: String {
        if isConnected { return L10n.t("connect.protected", lang) }
        if isBusy { return L10n.t("connect.connecting", lang) }
        return L10n.t("connect.connect", lang)
    }
}
