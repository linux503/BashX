import SwiftUI

/// Compact website reachability — uses mihomo delay API first, mixed-port as fallback.
struct WebsiteProbeStripMac: View {
    let state: AppState
    var compact: Bool = false
    /// Hide title when an outer collapsible header already shows「网站连通」.
    var showTitle: Bool = true
    @Environment(\.bashxAppearance) private var appearance
    @State private var statuses: [String: WebsiteProbe.Status] = [:]
    @State private var isRunning = false
    @State private var lastRun: Date?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 8) {
                if showTitle {
                    Text(L10n.t("probe.title", state.settings.uiLanguage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                }
                Spacer(minLength: 0)
                if let lastRun {
                    Text(lastRun, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
                testButton
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(WebsiteProbe.defaults) { target in
                    probeChip(target)
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private var testButton: some View {
        Button {
            Task { await runAll() }
        } label: {
            HStack(spacing: 4) {
                if isRunning {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                }
                Text(isRunning ? L10n.t("probe.testing", state.settings.uiLanguage) : L10n.t("probe.test", state.settings.uiLanguage))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(BashXTheme.accent(for: appearance))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(BashXTheme.accentSoft(for: appearance)))
        }
        .buttonStyle(.plain)
        .disabled(isRunning || !state.coreRunning)
    }

    private func probeChip(_ target: WebsiteProbe.Target) -> some View {
        let status = statuses[target.id] ?? .idle
        return Button {
            Task { await runOne(target) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chipColor(status))
                Text(target.localizedTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(status.label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(chipColor(status))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chipBackground(status))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(chipColor(status).opacity(status == .idle ? 0 : 0.3), lineWidth: 0.8)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isRunning || !state.coreRunning)
        .help("\(target.proxyGroup) · \(target.url)")
    }

    private func chipColor(_ status: WebsiteProbe.Status) -> Color {
        switch status {
        case .idle: return BashXTheme.secondaryLabel(for: appearance)
        case .testing: return BashXTheme.accent(for: appearance)
        case .ok: return BashXTheme.good(for: appearance)
        case .fail: return BashXTheme.bad(for: appearance)
        }
    }

    private func chipBackground(_ status: WebsiteProbe.Status) -> Color {
        switch status {
        case .idle: return BashXTheme.secondaryFill(for: appearance)
        case .testing: return BashXTheme.accentSoft(for: appearance)
        case .ok: return BashXTheme.good(for: appearance).opacity(0.12)
        case .fail: return BashXTheme.bad(for: appearance).opacity(0.12)
        }
    }

    private func runAll() async {
        guard state.coreRunning else { return }
        isRunning = true
        defer { isRunning = false }
        for target in WebsiteProbe.defaults {
            statuses[target.id] = .testing
        }
        let results = await WebsiteProbe.probeAllViaController(
            controller: state.settings.externalController,
            secret: state.settings.secret,
            port: state.settings.mixedPort,
            targets: WebsiteProbe.defaults,
            timeoutMs: 8000
        )
        statuses = results
        lastRun = Date()
    }

    private func runOne(_ target: WebsiteProbe.Target) async {
        guard state.coreRunning else { return }
        statuses[target.id] = .testing
        var status = await WebsiteProbe.probeViaController(
            target,
            controller: state.settings.externalController,
            secret: state.settings.secret,
            timeoutMs: 8000
        )
        if case .fail = status {
            status = await WebsiteProbe.probeViaMixedPort(
                target,
                port: state.settings.mixedPort,
                timeout: 8
            )
        }
        statuses[target.id] = status
        lastRun = Date()
    }
}
