import AppKit
import SwiftUI

/// Shared density tokens for the Mac full panel — keep spacing/radii/fonts aligned.
enum PanelMetrics {
    /// Tuned for default full-panel window (~1000×680).
    static let sidebarWidth: CGFloat = 198
    static let sidebarInset: CGFloat = 7
    static let sidebarStack: CGFloat = 7
    static let cardPad: CGFloat = 7
    static let cardRadius: CGFloat = 10
    static let chipRadius: CGFloat = 7
    static let topBarHeight: CGFloat = 44
    /// Fixed sidebar card heights — blocks must not grow/shrink with content.
    static let sidebarTrafficHeight: CGFloat = 144
    static let sidebarNodeCardHeight: CGFloat = 56
    static let sidebarProxyCardHeight: CGFloat = 64
    static let sidebarSubsCardHeight: CGFloat = 112
    static let sidebarSettingsCardHeight: CGFloat = 178
    static let sidebarToggleRowHeight: CGFloat = 32
    static let sidebarStartButtonHeight: CGFloat = 28
    /// SF Pro — default design reads cleaner on macOS than rounded everywhere.
    static let heroTitle = Font.system(size: 12.5, weight: .semibold)
    static let sectionTitle = Font.system(size: 10.5, weight: .semibold)
    static let body = Font.system(size: 10.5, weight: .medium)
    static let caption = Font.system(size: 9.5, weight: .regular)
    static let micro = Font.system(size: 8.5, weight: .regular)
    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monoLarge = Font.system(size: 11.5, weight: .semibold, design: .monospaced)

    static let bodyTracking: CGFloat = 0.15
    static let captionTracking: CGFloat = 0.2
}

enum BashXTheme {
    // Sky blue (天蓝) — unified accent across panel, sidebar, and nodes
    static func accent(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.42, green: 0.78, blue: 1.00)
            : Color(red: 0.18, green: 0.62, blue: 0.98)
    }

    static func accentSoft(for appearance: AppAppearance) -> Color {
        accent(for: appearance).opacity(appearance == .dark ? 0.24 : 0.12)
    }

    static func accentGlow(for appearance: AppAppearance) -> Color {
        accent(for: appearance).opacity(appearance == .dark ? 0.32 : 0.18)
    }

    /// Window / panel backdrop
    static func canvas(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.05, green: 0.07, blue: 0.11)
            : Color(red: 0.95, green: 0.97, blue: 1.00)
    }

    /// Cards, side panels — clearly elevated above canvas in dark
    static func card(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.14, green: 0.16, blue: 0.20)
            : Color(nsColor: .controlBackgroundColor)
    }

    /// Inputs, chips
    static func field(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.18, green: 0.21, blue: 0.26)
            : Color(nsColor: .textBackgroundColor)
    }

    static func sidebarTint(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.07, green: 0.09, blue: 0.14)
            : Color(red: 0.92, green: 0.96, blue: 1.00)
    }

    static func canvasNSColor(for appearance: AppAppearance) -> NSColor {
        NSColor(canvas(for: appearance))
    }

    /// Primary body text — deeper ink in light mode
    static func primaryLabel(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.94, green: 0.95, blue: 0.97)
            : Color(red: 0.12, green: 0.16, blue: 0.22)
    }

    /// Secondary body text (replaces washed-out .secondary on dark)
    static func secondaryLabel(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.78, green: 0.82, blue: 0.88)
            : Color(red: 0.28, green: 0.34, blue: 0.42)
    }

    /// Tertiary / meta text
    static func tertiaryLabel(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.58, green: 0.63, blue: 0.70)
            : Color(red: 0.42, green: 0.48, blue: 0.56)
    }

    static let accent = Color(red: 0.18, green: 0.62, blue: 0.98)
    static let accentSoft = Color(red: 0.18, green: 0.62, blue: 0.98).opacity(0.12)
    static let accentGlow = Color(red: 0.55, green: 0.82, blue: 1.00).opacity(0.28)
    static let good = Color(red: 0.42, green: 0.72, blue: 0.58)
    static let warn = Color(red: 0.92, green: 0.68, blue: 0.38)
    static let bad = Color(red: 0.88, green: 0.45, blue: 0.48)

    static func good(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 0.45, green: 0.90, blue: 0.68)
            : good
    }

    static func warn(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 1.00, green: 0.78, blue: 0.42)
            : warn
    }

    static func bad(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color(red: 1.00, green: 0.55, blue: 0.58)
            : bad
    }

    static func separator(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color.white.opacity(0.18)
            : Color.primary.opacity(0.10)
    }

    static func hairline(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color.white.opacity(0.14)
            : Color.primary.opacity(0.08)
    }

    static func secondaryFill(for appearance: AppAppearance) -> Color {
        appearance == .dark
            ? Color.white.opacity(0.10)
            : Color.primary.opacity(0.045)
    }

    static let separator = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.08)
    static let secondaryFill = Color.primary.opacity(0.045)

    static func delayColor(_ ms: Int?, appearance: AppAppearance = .light) -> Color {
        guard let ms else { return secondaryLabel(for: appearance) }
        if ms < 0 { return bad(for: appearance) }
        if ms < 150 { return good(for: appearance) }
        if ms < 400 { return warn(for: appearance) }
        return bad(for: appearance)
    }

    static func proxyModeColor(_ mode: ProxyMode, appearance: AppAppearance = .light) -> Color {
        switch mode {
        case .rule: return accent(for: appearance)
        case .global: return warn(for: appearance)
        case .direct:
            return appearance == .dark
                ? Color(red: 0.72, green: 0.76, blue: 0.84)
                : Color(red: 0.45, green: 0.52, blue: 0.62)
        }
    }
}

// MARK: - Theme wrapper

struct BashXThemed<Content: View>: View {
    let appearance: AppAppearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .preferredColorScheme(appearance.colorScheme)
            .tint(BashXTheme.accent(for: appearance))
            .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
            .environment(\.bashxAppearance, appearance)
            .id(appearance.rawValue)
    }
}

/// Rebuild open panel/settings windows when theme changes.
enum ThemeRefresh {
    @MainActor
    static func apply(state: AppState) {
        PanelPresenter.shared.refreshAppearance(state: state)
        SettingsPresenter.shared.refreshAppearance(state: state)
    }
}

private struct BashXAppearanceKey: EnvironmentKey {
    static let defaultValue: AppAppearance = .light
}

extension EnvironmentValues {
    var bashxAppearance: AppAppearance {
        get { self[BashXAppearanceKey.self] }
        set { self[BashXAppearanceKey.self] = newValue }
    }
}

struct SettingsCardShell<Content: View>: View {
    @Environment(\.bashxAppearance) private var appearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PanelAtmosphere()
            content()
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BashXTheme.card(for: appearance))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: appearance == .dark ? 1 : 0.5)
                        )
                }
                .padding(10)
        }
    }
}

// MARK: - Background

struct PanelAtmosphere: View {
    @Environment(\.bashxAppearance) private var appearance

    var body: some View {
        // Flat canvas only — multi-layer gradients were janky on Apple Silicon menu-bar hosts.
        BashXTheme.canvas(for: appearance)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Soft static backdrop for Mac minimal home (panel window only — not the menu bar).
/// Gradients only — large blurs were re-rasterized whenever the panel redrawn.
struct MinimalHomeBackdrop: View {
    @Environment(\.bashxAppearance) private var appearance

    var body: some View {
        ZStack {
            BashXTheme.canvas(for: appearance)
            LinearGradient(
                colors: [
                    BashXTheme.accent(for: appearance).opacity(appearance == .dark ? 0.18 : 0.12),
                    Color.clear,
                    BashXTheme.good(for: appearance).opacity(appearance == .dark ? 0.10 : 0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(appearance == .dark ? 0.04 : 0.28),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Prominent 极简 / 完整 layout switch used in both homes.
struct PanelHomeModeToggle: View {
    @Environment(\.bashxAppearance) private var appearance
    let isMinimal: Bool
    let lang: AppLanguage
    let onSelectMinimal: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            toggleSide(
                title: L10n.t("mac.minimal.mode", lang),
                systemImage: "sparkles",
                selected: isMinimal
            ) {
                onSelectMinimal(true)
            }
            toggleSide(
                title: L10n.t("mac.minimal.full", lang),
                systemImage: "rectangle.split.3x3.fill",
                selected: !isMinimal
            ) {
                onSelectMinimal(false)
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BashXTheme.card(for: appearance),
                            BashXTheme.secondaryFill(for: appearance).opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    BashXTheme.accent(for: appearance).opacity(0.42),
                                    BashXTheme.good(for: appearance).opacity(0.16),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: BashXTheme.accent(for: appearance).opacity(0.18), radius: 10, y: 3)
        }
        .help(isMinimal ? L10n.t("mac.minimal.toFull", lang) : L10n.t("mac.minimal.toSimple", lang))
    }

    private func toggleSide(
        title: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? Color.white : BashXTheme.secondaryLabel(for: appearance))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        selected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        BashXTheme.accent(for: appearance),
                                        Color(red: 0.42, green: 0.78, blue: 1.0),
                                        BashXTheme.good(for: appearance).opacity(0.82),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                selected
                                    ? Color.white.opacity(appearance == .dark ? 0.26 : 0.5)
                                    : BashXTheme.separator(for: appearance).opacity(0.16),
                                lineWidth: selected ? 0.8 : 0.4
                            )
                    )
                    .shadow(color: selected ? BashXTheme.accent(for: appearance).opacity(0.3) : .clear, radius: 6, y: 2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PanelPressButtonStyle())
        .animation(.easeOut(duration: 0.14), value: selected)
    }
}

// MARK: - Surfaces (flat, native)

struct GlassSurface: View {
    @Environment(\.bashxAppearance) private var appearance
    var cornerRadius: CGFloat = 8
    var emphasized: Bool = false
    var compact: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(emphasized ? BashXTheme.card(for: appearance) : BashXTheme.field(for: appearance))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
            )
    }
}

struct GlassDivider: View {
    var body: some View {
        Divider()
    }
}

struct PanelSection<Content: View>: View {
    @Environment(\.bashxAppearance) private var appearance
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(PanelMetrics.sectionTitle)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            content()
        }
        .padding(PanelMetrics.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }
}

struct StatusPill: View {
    @Environment(\.bashxAppearance) private var appearance
    let title: String
    let active: Bool
    var activeColor: Color?

    private var tint: Color { activeColor ?? BashXTheme.accent(for: appearance) }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? tint : BashXTheme.tertiaryLabel(for: appearance))
                .frame(width: 4, height: 4)
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .medium, design: .rounded))
                .foregroundStyle(active ? BashXTheme.primaryLabel(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(active ? tint.opacity(appearance == .dark ? 0.20 : 0.12) : BashXTheme.secondaryFill(for: appearance))
        }
    }
}

struct SidebarSectionHeader: View {
    @Environment(\.bashxAppearance) private var appearance
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }
            Text(title)
                .font(PanelMetrics.sectionTitle)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            Spacer(minLength: 0)
        }
    }
}

struct ActionChip: View {
    @Environment(\.bashxAppearance) private var appearance
    let title: String
    let systemImage: String
    var enabled: Bool = true
    var emphasized: Bool = false
    let action: () -> Void

    private var labelColor: Color {
        if !enabled { return BashXTheme.tertiaryLabel(for: appearance) }
        if emphasized { return BashXTheme.accent(for: appearance) }
        return BashXTheme.secondaryLabel(for: appearance)
    }

    private var iconColor: Color {
        if !enabled { return BashXTheme.tertiaryLabel(for: appearance) }
        if emphasized { return BashXTheme.accent(for: appearance) }
        return BashXTheme.accent(for: appearance).opacity(appearance == .dark ? 0.85 : 0.72)
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .foregroundStyle(labelColor)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
            }
            .font(.caption2.weight(emphasized ? .semibold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chipFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(chipBorder, lineWidth: emphasized ? 1 : 0.5)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .animation(nil, value: emphasized)
    }

    private var chipFill: Color {
        if emphasized {
            return BashXTheme.accentSoft(for: appearance)
        }
        return appearance == .dark
            ? BashXTheme.field(for: appearance)
            : BashXTheme.card(for: appearance)
    }

    private var chipBorder: Color {
        if emphasized {
            return BashXTheme.accent(for: appearance).opacity(appearance == .dark ? 0.55 : 0.35)
        }
        return BashXTheme.separator(for: appearance)
    }
}

struct SoftCard<Content: View>: View {
    var padding: CGFloat = PanelMetrics.cardPad
    var cornerRadius: CGFloat = PanelMetrics.cardRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background { GlassSurface(cornerRadius: cornerRadius) }
    }
}

struct SoftField<Content: View>: View {
    @Environment(\.bashxAppearance) private var appearance
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BashXTheme.field(for: appearance))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                    )
            }
    }
}

struct MetricTile: View {
    @Environment(\.bashxAppearance) private var appearance
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TopBarRateBadge: View {
    @Environment(\.bashxAppearance) private var appearance
    @ObservedObject var panel: PanelRateStore

    var body: some View {
        HStack(spacing: 6) {
            rateChip(
                title: "下行",
                symbol: "arrow.down.circle.fill",
                value: panel.downMbps,
                tint: BashXTheme.accent(for: appearance)
            )
            rateChip(
                title: "上行",
                symbol: "arrow.up.circle.fill",
                value: panel.upMbps,
                tint: Color(red: 0.95, green: 0.55, blue: 0.18)
            )
        }
        .animation(nil, value: panel.downMbps)
        .animation(nil, value: panel.upMbps)
    }

    private func rateChip(title: String, symbol: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                    Text("/s")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.10), tint.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                )
        }
    }
}

/// Instant press feedback for panel cards / chips (no layout animation).
struct PanelPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(nil, value: configuration.isPressed)
    }
}
