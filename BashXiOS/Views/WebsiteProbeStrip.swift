import SwiftUI

/// Common-site reachability row under Home quick controls.
struct WebsiteProbeStrip: View {
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var state: IOSAppState
    @State private var statuses: [String: WebsiteProbe.Status] = [:]
    @State private var isRunning = false
    @State private var lastRun: Date?

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("probe.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastRun {
                    Text(lastRun, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Button {
                    Task { await runAll() }
                } label: {
                    HStack(spacing: 4) {
                        if isRunning {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.bold))
                        }
                        Text(isRunning ? t("probe.testing") : t("probe.test"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(IOSTheme.accentDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(IOSTheme.accentSoft))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(WebsiteProbe.defaults) { target in
                    probeChip(target)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(IOSTheme.cardBackground.opacity(0.7))
        }
        .id(lang.id)
        .onChange(of: vpn.isConnected) { connected in
            guard connected else { return }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard vpn.isConnected else { return }
                await runAll()
            }
        }
    }

    private func probeChip(_ target: WebsiteProbe.Target) -> some View {
        let status = statuses[target.id] ?? .idle
        return Button {
            Task { await runOne(target) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: target.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(chipColor(status))
                Text(target.localizedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(status.label)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(chipColor(status))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chipBackground(status))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(chipColor(status).opacity(status == .idle ? 0 : 0.25), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isRunning && status == .testing)
    }

    private func chipColor(_ status: WebsiteProbe.Status) -> Color {
        switch status {
        case .idle: return .secondary
        case .testing: return IOSTheme.accent
        case .ok: return IOSTheme.good
        case .fail: return IOSTheme.bad
        }
    }

    private func chipBackground(_ status: WebsiteProbe.Status) -> Color {
        switch status {
        case .idle: return IOSTheme.tertiaryFill
        case .testing: return IOSTheme.accentSoft
        case .ok: return IOSTheme.good.opacity(0.12)
        case .fail: return IOSTheme.bad.opacity(0.1)
        }
    }

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        for target in WebsiteProbe.defaults {
            statuses[target.id] = .testing
        }
        let results = await vpn.probeWebsites(timeoutMs: 12_000)
        for target in WebsiteProbe.defaults {
            statuses[target.id] = results[target.id] ?? .fail(L10n.t("probe.noResult"))
        }
        isRunning = false
        lastRun = Date()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func runOne(_ target: WebsiteProbe.Target) async {
        statuses[target.id] = .testing
        let results = await vpn.probeWebsites(targets: [target])
        statuses[target.id] = results[target.id] ?? .fail(L10n.t("probe.noResult"))
        lastRun = Date()
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
