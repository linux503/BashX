import SwiftUI

struct IOSConnectControl: View {
    let isConnected: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var pulse = false
    @State private var rotation: Double = 0
    @State private var pressScale: CGFloat = 1

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pressScale = 0.94 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressScale = 1 }
            }
            action()
        } label: {
            ZStack {
                // Ambient glow
                Circle()
                    .fill(centerShadow.opacity(isConnected ? 0.28 : 0.14))
                    .frame(width: 210, height: 210)
                    .blur(radius: 28)
                    .scaleEffect(pulse && isConnected ? 1.08 : 1)

                Circle()
                    .strokeBorder(ringGradient, lineWidth: 3.5)
                    .frame(width: 182, height: 182)
                    .opacity(0.9)

                if isConnected {
                    Circle()
                        .strokeBorder(IOSTheme.good.opacity(0.35), lineWidth: 2)
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                        .opacity(pulse ? 0.25 : 0.7)
                }

                if isBusy {
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(IOSTheme.warn.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(rotation))
                }

                Circle()
                    .fill(centerGradient)
                    .frame(width: 150, height: 150)
                    .shadow(color: centerShadow.opacity(0.4), radius: 22, y: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    )

                VStack(spacing: 10) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: isConnected ? "checkmark.shield.fill" : "power")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .symbolRenderingMode(.hierarchical)
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
        .accessibilityLabel(isConnected ? "断开 VPN" : "连接 VPN")
        .onAppear {
            pulse = isConnected
            if isBusy { startSpin() }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = isConnected || true
            }
            // Keep pulse only meaningful when connected
            pulse = isConnected
            if isConnected {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .onChange(of: isConnected) { connected in
            if connected {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
        .onChange(of: isBusy) { busy in
            if busy { startSpin() } else { rotation = 0 }
        }
    }

    private func startSpin() {
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
        if isConnected { return "已保护" }
        if isBusy { return "连接中" }
        return "连接"
    }
}
