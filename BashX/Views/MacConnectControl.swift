import SwiftUI

/// Mac minimal home connect control — mirrors iOS look with cheap motion
/// (idle/connected stay static; only「连接中」spins). Forever blur/orbit/radar
/// previously kept the panel window at 30–60fps even when idle.
struct MacConnectControl: View {
    let isConnected: Bool
    let isBusy: Bool
    let appearance: AppAppearance
    var language: AppLanguage = .system
    let action: () -> Void

    @State private var rotation: Double = 0
    @State private var pressScale: CGFloat = 1

    private var lang: AppLanguage { language }

    var body: some View {
        Button(action: tapConnect) {
            connectArtwork
                .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(isConnected ? L10n.t("mac.minimal.disconnect", lang) : L10n.t("mac.minimal.connect", lang))
        .onChange(of: isBusy) { busy in
            if busy { startSpin() } else { rotation = 0 }
        }
        .onAppear {
            if isBusy { startSpin() }
        }
    }

    private var connectArtwork: some View {
        ZStack {
            // Soft glow without animated blur scale (blur+scale forever was the lag).
            Circle()
                .fill(centerShadow.opacity(isConnected ? 0.16 : 0.08))
                .frame(width: 200, height: 200)
                .allowsHitTesting(false)

            // Static decorative rings
            Circle()
                .strokeBorder(centerShadow.opacity(0.18), lineWidth: 1)
                .frame(width: 172, height: 172)
                .allowsHitTesting(false)
            Circle()
                .strokeBorder(centerShadow.opacity(0.10), lineWidth: 1)
                .frame(width: 188, height: 188)
                .allowsHitTesting(false)

            mainRing

            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(BashXTheme.warn.opacity(0.55), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: 176, height: 176)
                    .rotationEffect(.degrees(rotation))
                    .allowsHitTesting(false)
            }

            centerDisc
            centerContent
        }
        .frame(width: 220, height: 220)
        .contentShape(Circle())
    }

    private var mainRing: some View {
        Circle()
            .strokeBorder(ringGradient, lineWidth: 3.2)
            .frame(width: 164, height: 164)
            .opacity(0.92)
            .shadow(
                color: centerShadow.opacity(isConnected ? 0.28 : 0.10),
                radius: isConnected ? 8 : 3
            )
            .allowsHitTesting(false)
    }

    private var centerDisc: some View {
        Circle()
            .fill(centerGradient)
            .frame(width: 132, height: 132)
            .shadow(color: centerShadow.opacity(0.36), radius: 14, y: 8)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
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
