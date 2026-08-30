import SwiftUI

struct IOSConnectControl: View {
    let isConnected: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    @EnvironmentObject private var state: IOSAppState
    @State private var pulse = false
    @State private var rotation: Double = 0
    @State private var pressScale: CGFloat = 1
    @State private var orbitAngle: Double = 0
    @State private var radarSweep: Double = 0
    @State private var breath = false
    @State private var connectBurst = false

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        Button(action: tapConnect) {
            connectArtwork
                .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(
            isConnected || isBusy
                ? t("connect.a11y.disconnect")
                : t("connect.a11y.connect")
        )
        .onAppear { syncAnimations() }
        .onChange(of: isConnected) { _ in syncAnimations() }
        .onChange(of: isBusy) { busy in
            handleBusyChange(busy)
        }
    }

    private var connectArtwork: some View {
        ZStack {
            ambientGlow
            connectingOrbits
            idleOrbits
            connectedOrbits
            mainRing
            connectedSatellites
            centerDisc
            centerContent
        }
    }

    private var ambientGlow: some View {
        Circle()
            .fill(centerShadow.opacity(glowOpacity))
            .frame(width: isBusy ? 260 : 236, height: isBusy ? 260 : 236)
            .blur(radius: isBusy ? 42 : 34)
            .scaleEffect(breath ? 1.14 : 0.96)
    }

    private var glowOpacity: Double {
        if isConnected { return 0.34 }
        if isBusy { return breath ? 0.42 : 0.22 }
        return breath ? 0.20 : 0.12
    }

    @ViewBuilder
    private var connectingOrbits: some View {
        if isBusy {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(connectingRingGradient, lineWidth: 2.2 - CGFloat(i) * 0.4)
                    .frame(width: 188 + CGFloat(i) * 22, height: 188 + CGFloat(i) * 22)
                    .rotationEffect(.degrees(orbitAngle * (i % 2 == 0 ? 1.2 : -0.9) + Double(i) * 40))
                    .opacity(0.7)
                    .blur(radius: i == 2 ? 1.2 : 0)
            }
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(i % 2 == 0 ? Color.white : IOSTheme.warn)
                    .frame(width: i % 2 == 0 ? 5 : 4, height: i % 2 == 0 ? 5 : 4)
                    .shadow(color: IOSTheme.warn.opacity(0.9), radius: 5)
                    .offset(y: -108)
                    .rotationEffect(.degrees(orbitAngle * 1.4 + Double(i) * 60))
            }
        }
    }

    private var connectingRingGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.55),
                IOSTheme.warn.opacity(0.7),
                Color.black.opacity(0.35),
                Color.white.opacity(0),
            ],
            center: .center
        )
    }

    @ViewBuilder
    private var idleOrbits: some View {
        if !isConnected && !isBusy {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(idleRingGradient, lineWidth: 1.2)
                    .frame(width: 176 + CGFloat(i) * 16, height: 176 + CGFloat(i) * 16)
                    .rotationEffect(.degrees(orbitAngle * (i == 0 ? 1 : -0.8)))
                    .opacity(0.55)
            }
        }
    }

    private var idleRingGradient: AngularGradient {
        AngularGradient(
            colors: [
                centerShadow.opacity(0),
                centerShadow.opacity(0.35),
                IOSTheme.accentBright.opacity(0.2),
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
                        IOSTheme.good.opacity(0.18 - Double(i) * 0.04),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 6])
                    )
                    .frame(width: 168 + CGFloat(i) * 18, height: 168 + CGFloat(i) * 18)
                    .rotationEffect(.degrees(orbitAngle + Double(i) * 24))
                    .opacity(pulse ? 0.85 : 0.45)
            }
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(radarGradient, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .frame(width: 198, height: 198)
                .rotationEffect(.degrees(radarSweep))
                .blur(radius: 0.5)
            Circle()
                .strokeBorder(IOSTheme.good.opacity(0.40), lineWidth: 2)
                .frame(width: 206, height: 206)
                .scaleEffect(pulse ? 1.10 : 0.92)
                .opacity(pulse ? 0.2 : 0.75)
        }
    }

    private var radarGradient: AngularGradient {
        AngularGradient(
            colors: [IOSTheme.good.opacity(0), IOSTheme.good.opacity(0.55), IOSTheme.good.opacity(0)],
            center: .center
        )
    }

    private var mainRing: some View {
        Circle()
            .strokeBorder(ringGradient, lineWidth: isBusy ? 4.5 : 3.5)
            .frame(width: 182, height: 182)
            .opacity(0.92)
            .shadow(
                color: centerShadow.opacity(isConnected || isBusy ? 0.45 : 0.12),
                radius: isConnected || isBusy ? 14 : 4
            )
            .scaleEffect(isBusy && connectBurst ? 1.04 : 1)
    }

    @ViewBuilder
    private var connectedSatellites: some View {
        if isConnected {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(IOSTheme.good)
                    .frame(width: 6, height: 6)
                    .shadow(color: IOSTheme.good.opacity(0.8), radius: 4)
                    .offset(y: -91)
                    .rotationEffect(.degrees(orbitAngle + Double(i) * 90))
            }
        }
    }

    private var centerDisc: some View {
        Circle()
            .fill(centerGradient)
            .frame(width: 150, height: 150)
            .scaleEffect(breath && (isConnected || isBusy) ? 1.04 : 1)
            .shadow(color: centerShadow.opacity(0.45), radius: 22, y: 12)
            .overlay(Circle().strokeBorder(Color.white.opacity(isBusy ? 0.4 : 0.28), lineWidth: 1))
            .overlay { centerDiscOverlay }
    }

    @ViewBuilder
    private var centerDiscOverlay: some View {
        if isConnected {
            Circle()
                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .padding(10)
        }
        if isBusy {
            Circle()
                .strokeBorder(busyInnerGradient, lineWidth: 1.4)
                .padding(8)
                .rotationEffect(.degrees(rotation))
        }
    }

    private var busyInnerGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.clear,
                Color.black.opacity(0.25),
                Color.clear,
                Color.white.opacity(0.35),
            ],
            center: .center
        )
    }

    private var centerContent: some View {
        VStack(spacing: 8) {
            if isBusy {
                TaijiFishSpinner(size: 54, spinning: true, glow: IOSTheme.warn)
                    .frame(height: 58)
            } else {
                Image(systemName: isConnected ? "checkmark.shield.fill" : "power")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(breath && isConnected ? 1.06 : 1)
            }
            Text(centerLabel)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
    }

    private func tapConnect() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pressScale = 0.94 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressScale = 1 }
        }
        action()
    }

    private func handleBusyChange(_ busy: Bool) {
        if busy {
            startSpin()
            connectBurst = false
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                connectBurst = true
            }
        } else {
            rotation = 0
            connectBurst = false
        }
        syncAnimations()
    }

    private func syncAnimations() {
        if isBusy { startSpin() }
        breath = false
        pulse = false
        withAnimation(.easeInOut(duration: isConnected ? 1.9 : (isBusy ? 1.2 : 2.8)).repeatForever(autoreverses: true)) {
            breath = true
            if isConnected { pulse = true }
        }
        withAnimation(.linear(duration: isBusy ? 6 : (isConnected ? 10 : 16)).repeatForever(autoreverses: false)) {
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
            return LinearGradient(colors: [IOSTheme.good, IOSTheme.good.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if isBusy {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    IOSTheme.warn,
                    Color(red: 0.12, green: 0.12, blue: 0.16),
                    IOSTheme.warn.opacity(0.7),
                    Color.white.opacity(0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return IOSTheme.accentGradient
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
                colors: [
                    Color(red: 1.0, green: 0.82, blue: 0.38),
                    Color(red: 0.95, green: 0.55, blue: 0.12),
                    Color(red: 0.35, green: 0.22, blue: 0.08),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return IOSTheme.accentGradient
    }

    private var centerShadow: Color {
        if isConnected { return IOSTheme.good }
        if isBusy { return IOSTheme.warn }
        return IOSTheme.accent
    }

    private var centerLabel: String {
        if isConnected { return t("connect.protected") }
        if isBusy { return t("connect.cancel") }
        return t("connect.connect")
    }
}

// MARK: - 太极双鱼

private struct TaijiFishSpinner: View {
    var size: CGFloat = 52
    var spinning: Bool = true
    var glow: Color = IOSTheme.warn

    @State private var rotation: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(glow.opacity(pulse ? 0.45 : 0.18))
                .frame(width: size * 1.55, height: size * 1.55)
                .blur(radius: size * 0.28)
                .scaleEffect(pulse ? 1.12 : 0.92)

            TaijiFishMark(size: size)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .rotationEffect(.degrees(rotation))

            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.85),
                            glow.opacity(0.6),
                            Color.white.opacity(0),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: max(2, size * 0.045), lineCap: .round)
                )
                .frame(width: size * 1.18, height: size * 1.18)
                .rotationEffect(.degrees(-rotation * 1.35))
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear { sync() }
        .onChange(of: spinning) { _ in sync() }
    }

    private func sync() {
        pulse = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = true
        }
        guard spinning else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 1.65).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct TaijiFishMark: View {
    var size: CGFloat

    private let yin = Color(red: 0.08, green: 0.09, blue: 0.12)
    private let yang = Color(red: 0.97, green: 0.97, blue: 0.94)

    var body: some View {
        let eye = size * 0.14
        let lobe = size * 0.5

        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color(red: 1.0, green: 0.82, blue: 0.35).opacity(0.7),
                            Color.white.opacity(0.2),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.5, size * 0.035)
                )
                .frame(width: size, height: size)

            Circle()
                .fill(yang)
                .frame(width: size - 2, height: size - 2)

            HStack(spacing: 0) {
                Rectangle().fill(yin)
                Color.clear
            }
            .frame(width: size - 2, height: size - 2)
            .clipShape(Circle())

            Circle()
                .fill(yang)
                .frame(width: lobe, height: lobe)
                .offset(y: -size * 0.25)

            Circle()
                .fill(yin)
                .frame(width: lobe, height: lobe)
                .offset(y: size * 0.25)

            Circle()
                .fill(yin)
                .frame(width: eye, height: eye)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                .offset(y: -size * 0.25)

            Circle()
                .fill(yang)
                .frame(width: eye, height: eye)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.6))
                .offset(y: size * 0.25)

            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.08, height: size * 0.18)
                .offset(x: -size * 0.22, y: -size * 0.08)

            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.08, height: size * 0.18)
                .offset(x: size * 0.22, y: size * 0.08)
        }
        .frame(width: size, height: size)
    }
}
