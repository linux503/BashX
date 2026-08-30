import SwiftUI

// MARK: - Premium design tokens (Express / Nord / Surfshark class)

enum IOSTheme {
    // Brand — sky azure (天蓝色)
    static let accent = Color(red: 0.22, green: 0.64, blue: 0.96)
    static let accentDeep = Color(red: 0.10, green: 0.42, blue: 0.78)
    static let accentBright = Color(red: 0.52, green: 0.82, blue: 1.0)
    static let accentSoft = Color(red: 0.22, green: 0.64, blue: 0.96).opacity(0.16)
    static let accentMuted = Color(red: 0.22, green: 0.64, blue: 0.96).opacity(0.10)

    static let ink = Color(red: 0.08, green: 0.14, blue: 0.22)
    static let mist = Color(red: 0.92, green: 0.96, blue: 1.0)

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.84, blue: 1.0),
            Color(red: 0.22, green: 0.64, blue: 0.96),
            Color(red: 0.08, green: 0.40, blue: 0.78),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroAtmosphere = LinearGradient(
        colors: [
            Color(red: 0.22, green: 0.64, blue: 0.96).opacity(0.28),
            Color(red: 0.30, green: 0.58, blue: 0.92).opacity(0.12),
            Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.4),
            Color(.systemGroupedBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let good = Color(red: 0.18, green: 0.84, blue: 0.44)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.28)
    static let bad = Color(red: 1.0, green: 0.32, blue: 0.28)

    static let chartDown = Color(red: 0.98, green: 0.52, blue: 0.38)
    static let chartUp = Color(red: 0.28, green: 0.70, blue: 0.98)
    static let chartDownGradient = LinearGradient(
        colors: [chartDown.opacity(0.45), chartDown.opacity(0.02)],
        startPoint: .top, endPoint: .bottom
    )
    static let chartUpGradient = LinearGradient(
        colors: [chartUp.opacity(0.35), chartUp.opacity(0.02)],
        startPoint: .top, endPoint: .bottom
    )

    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let tertiaryFill = Color(.tertiarySystemGroupedBackground)
    static let cardStroke = Color.primary.opacity(0.06)

    static let cardRadius: CGFloat = 22
    static let innerRadius: CGFloat = 14

    static let brandFont = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let displayFont = Font.system(.title2, design: .rounded).weight(.bold)

    static func delay(_ ms: Int?) -> Color {
        guard let ms else { return .secondary }
        if ms < 0 { return bad }
        if ms < 150 { return good }
        if ms < 400 { return warn }
        return bad
    }

    static func proxyModeColor(_ mode: ProxyMode) -> Color {
        switch mode {
        case .rule: return accent
        case .global: return warn
        case .direct: return Color(red: 0.45, green: 0.52, blue: 0.62)
        }
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Surfaces

struct IOSPageBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            IOSTheme.groupedBackground.ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    // Soft radial wash (premium VPN atmosphere)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    IOSTheme.accentBright.opacity(0.35),
                                    IOSTheme.accent.opacity(0.12),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: geo.size.width * 0.72
                            )
                        )
                        .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                        .offset(y: -geo.size.width * 0.35)
                        .blur(radius: 8)

                    Circle()
                        .fill(IOSTheme.accentDeep.opacity(0.10))
                        .frame(width: 220, height: 220)
                        .offset(x: geo.size.width * 0.32, y: 40)
                        .blur(radius: 40)

                    Circle()
                        .fill(Color(red: 0.2, green: 0.7, blue: 0.85).opacity(0.08))
                        .frame(width: 180, height: 180)
                        .offset(x: -geo.size.width * 0.3, y: 120)
                        .blur(radius: 36)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            content
        }
    }
}

struct IOSCard<Content: View>: View {
    var padding: CGFloat = 18
    var elevated: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: IOSTheme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: IOSTheme.cardRadius, style: .continuous)
                            .fill(IOSTheme.cardBackground.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IOSTheme.cardRadius, style: .continuous)
                            .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(elevated ? 0.06 : 0), radius: elevated ? 16 : 0, y: elevated ? 8 : 0)
            }
    }
}

struct IOSInsetRow<Label: View, Value: View>: View {
    @ViewBuilder var label: Label
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            label
            Spacer(minLength: 8)
            value
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct IOSStatusPill: View {
    let text: String
    let tone: Tone

    @State private var glow = false

    enum Tone { case connected, connecting, idle }

    var color: Color {
        switch tone {
        case .connected: return IOSTheme.good
        case .connecting: return IOSTheme.warn
        case .idle: return Color(.tertiaryLabel)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(tone == .connected || tone == .connecting ? 0.7 : 0), radius: glow ? 6 : 3)
                .scaleEffect(glow && tone != .idle ? 1.25 : 1)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone == .idle ? .secondary : color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(tone == .connected ? (glow ? 0.16 : 0.10) : 0.10))
                .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 0.5))
        )
        .onAppear { syncGlow() }
        .onChange(of: tone) { _ in syncGlow() }
    }

    private func syncGlow() {
        glow = false
        guard tone != .idle else { return }
        withAnimation(.easeInOut(duration: tone == .connecting ? 0.7 : 1.6).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}

struct IOSMetricTile: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: IOSTheme.innerRadius, style: .continuous)
                .fill(IOSTheme.tertiaryFill.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: IOSTheme.innerRadius, style: .continuous)
                        .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                )
        }
    }
}

struct IOSActionChip: View {
    let title: String
    let subtitle: String
    let icon: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(IOSTheme.accentSoft)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IOSTheme.accent)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: IOSTheme.innerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: IOSTheme.innerRadius, style: .continuous)
                            .fill(IOSTheme.cardBackground.opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IOSTheme.innerRadius, style: .continuous)
                            .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct IOSSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct IOSEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(IOSTheme.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(IOSTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text(title).font(.title3.weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(IOSTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IOSGroupedPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        IOSPageBackground { content }
    }
}
