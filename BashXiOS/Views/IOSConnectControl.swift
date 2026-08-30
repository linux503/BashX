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

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pressScale = 0.94 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressScale = 1 }
            }
            action()
        } label: {
            ZStack {
                // Soft ambient glow
                Circle()
                    .fill(centerShadow.opacity(isConnected ? 0.32 : 0.14))
                    .frame(width: 228, height: 228)
                    .blur(radius: 32)
                    .scaleEffect(breath && isConnected ? 1.12 : 1)

                // Tech orbit rings (connected)
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

                    // Radar sweep wedge
                    Circle()
                        .trim(from: 0, to: 0.18)
                        .stroke(
                            AngularGradient(
                                colors: [IOSTheme.good.opacity(0), IOSTheme.good.opacity(0.55), IOSTheme.good.opacity(0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .butt)
                        )
                        .frame(width: 198, height: 198)
                        .rotationEffect(.degrees(radarSweep))
                        .blur(radius: 0.5)

                    // Breathing halo
                    Circle()
                        .strokeBorder(IOSTheme.good.opacity(0.40), lineWidth: 2)
                        .frame(width: 206, height: 206)
                        .scaleEffect(pulse ? 1.10 : 0.92)
                        .opacity(pulse ? 0.2 : 0.75)
                }

                Circle()
                    .strokeBorder(ringGradient, lineWidth: 3.5)
                    .frame(width: 182, height: 182)
                    .opacity(0.92)
                    .shadow(color: centerShadow.opacity(isConnected ? 0.35 : 0.12), radius: isConnected ? 12 : 4)

                if isBusy {
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(IOSTheme.warn.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(rotation))
                }

                // Satellite dots on ring when connected
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

                Circle()
                    .fill(centerGradient)
                    .frame(width: 150, height: 150)
                    .scaleEffect(breath && isConnected ? 1.03 : 1)
                    .shadow(color: centerShadow.opacity(0.45), radius: 22, y: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .overlay {
                        if isConnected {
                            // Inner tech ring
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                                .padding(10)
                        }
                    }

                VStack(spacing: 10) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
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
            .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(isConnected ? t("connect.a11y.disconnect") : t("connect.a11y.connect"))
        .onAppear { syncAnimations() }
        .onChange(of: isConnected) { _ in syncAnimations() }
        .onChange(of: isBusy) { busy in
            if busy { startSpin() } else { rotation = 0 }
        }
    }

    private func syncAnimations() {
        if isBusy { startSpin() }
        if isConnected {
            pulse = false
            breath = false
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                pulse = true
                breath = true
            }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                orbitAngle = 360
            }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                radarSweep = 360
            }
        } else {
            pulse = false
            breath = false
            orbitAngle = 0
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
            return LinearGradient(colors: [IOSTheme.warn, IOSTheme.warn.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                colors: [Color(red: 1.0, green: 0.78, blue: 0.32), Color(red: 0.92, green: 0.58, blue: 0.12)],
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
        if isBusy { return t("connect.connecting") }
        return t("connect.connect")
    }
}
