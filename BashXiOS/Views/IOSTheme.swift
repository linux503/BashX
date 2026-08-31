import SwiftUI
import UIKit

// MARK: - Premium design tokens (adaptive light / dark)

enum IOSTheme {
    // Brand — sky azure; lift luminance in dark so it stays vivid on navy canvas
    static let accent = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 1.00, alpha: 1)
            : UIColor(red: 0.22, green: 0.64, blue: 0.96, alpha: 1)
    })
    static let accentDeep = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.62, blue: 0.98, alpha: 1)
            : UIColor(red: 0.10, green: 0.42, blue: 0.78, alpha: 1)
    })
    static let accentBright = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.88, blue: 1.00, alpha: 1)
            : UIColor(red: 0.52, green: 0.82, blue: 1.0, alpha: 1)
    })
    static let accentSoft = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 1.00, alpha: 0.22)
            : UIColor(red: 0.22, green: 0.64, blue: 0.96, alpha: 0.16)
    })
    static let accentMuted = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 1.00, alpha: 0.14)
            : UIColor(red: 0.22, green: 0.64, blue: 0.96, alpha: 0.10)
    })

    static let ink = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)
            : UIColor(red: 0.08, green: 0.14, blue: 0.22, alpha: 1)
    })
    static let mist = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1)
            : UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1)
    })

    static let accentGradient = LinearGradient(
        colors: [
            Color(uiColor: UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.55, green: 0.86, blue: 1.0, alpha: 1)
                    : UIColor(red: 0.55, green: 0.84, blue: 1.0, alpha: 1)
            }),
            accent,
            accentDeep,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let good = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.92, blue: 0.62, alpha: 1)
            : UIColor(red: 0.18, green: 0.84, blue: 0.44, alpha: 1)
    })
    static let warn = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1)
            : UIColor(red: 1.0, green: 0.74, blue: 0.28, alpha: 1)
    })
    static let bad = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.48, blue: 0.46, alpha: 1)
            : UIColor(red: 1.0, green: 0.32, blue: 0.28, alpha: 1)
    })

    static let chartDown = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.58, blue: 0.46, alpha: 1)
            : UIColor(red: 0.98, green: 0.52, blue: 0.38, alpha: 1)
    })
    static let chartUp = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 1)
            : UIColor(red: 0.28, green: 0.70, blue: 0.98, alpha: 1)
    })
    static let chartDownGradient = LinearGradient(
        colors: [chartDown.opacity(0.45), chartDown.opacity(0.02)],
        startPoint: .top, endPoint: .bottom
    )
    static let chartUpGradient = LinearGradient(
        colors: [chartUp.opacity(0.35), chartUp.opacity(0.02)],
        startPoint: .top, endPoint: .bottom
    )

    /// Deep navy canvas in dark — richer than plain system gray
    static let groupedBackground = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1)
            : UIColor.systemGroupedBackground
    })
    static let cardBackground = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    })
    static let tertiaryFill = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.19, blue: 0.25, alpha: 1)
            : UIColor.tertiarySystemGroupedBackground
    })
    static let cardStroke = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.label.withAlphaComponent(0.06)
    })
    static let cardShadow = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.45)
            : UIColor.black.withAlphaComponent(0.06)
    })

    /// Traffic chart well (was hard-coded light blue — unreadable in dark)
    static func trafficWellFill(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.13, blue: 0.20),
                    Color(red: 0.07, green: 0.11, blue: 0.17),
                    Color(red: 0.08, green: 0.14, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.97, blue: 1.0),
                Color(red: 0.88, green: 0.94, blue: 0.99),
                Color(red: 0.91, green: 0.96, blue: 0.95),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func trafficWellStroke(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    accentBright.opacity(0.35),
                    good.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.78, blue: 0.98).opacity(0.45),
                Color(red: 0.45, green: 0.85, blue: 0.80).opacity(0.25),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func trafficGrid(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.45, green: 0.62, blue: 0.78).opacity(0.18)
    }

    static func trafficEmptyLabel(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.45)
            : Color(red: 0.35, green: 0.48, blue: 0.58).opacity(0.75)
    }

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
        case .direct: return Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.68, blue: 0.76, alpha: 1)
                : UIColor(red: 0.45, green: 0.52, blue: 0.62, alpha: 1)
        })
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
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            IOSTheme.groupedBackground.ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    IOSTheme.accentBright.opacity(colorScheme == .dark ? 0.22 : 0.42),
                                    IOSTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.16),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 16,
                                endRadius: geo.size.width * 0.78
                            )
                        )
                        .frame(width: geo.size.width * 1.35, height: geo.size.width * 1.15)
                        .offset(y: -geo.size.width * 0.42)
                        .blur(radius: 10)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.78, blue: 1.0).opacity(colorScheme == .dark ? 0.10 : 0.18),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 160
                            )
                        )
                        .frame(width: 320, height: 220)
                        .offset(x: geo.size.width * 0.22, y: -20)
                        .blur(radius: 28)

                    Circle()
                        .fill(IOSTheme.accentDeep.opacity(colorScheme == .dark ? 0.10 : 0.12))
                        .frame(width: 240, height: 240)
                        .offset(x: geo.size.width * 0.34, y: 28)
                        .blur(radius: 44)

                    Circle()
                        .fill(Color(red: 0.2, green: 0.72, blue: 0.88).opacity(colorScheme == .dark ? 0.06 : 0.10))
                        .frame(width: 200, height: 200)
                        .offset(x: -geo.size.width * 0.32, y: 100)
                        .blur(radius: 40)
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
    @Environment(\.colorScheme) private var colorScheme
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
                            .fill(IOSTheme.cardBackground.opacity(colorScheme == .dark ? 0.88 : 0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IOSTheme.cardRadius, style: .continuous)
                            .strokeBorder(IOSTheme.cardStroke, lineWidth: colorScheme == .dark ? 0.8 : 0.5)
                    )
                    .shadow(
                        color: IOSTheme.cardShadow.opacity(elevated ? 1 : 0),
                        radius: elevated ? (colorScheme == .dark ? 20 : 16) : 0,
                        y: elevated ? 8 : 0
                    )
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
