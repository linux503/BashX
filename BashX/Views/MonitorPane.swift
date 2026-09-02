import SwiftUI

struct MonitorPane: View {
    let monitor: TrafficMonitor
    let panel: PanelRateStore
    @Binding var segment: MonitorSegment
    var coreAlive: Bool
    var lang: AppLanguage
    var onCloseAll: () -> Void
    @Environment(\.bashxAppearance) private var appearance

    enum MonitorSegment: String, CaseIterable, Identifiable {
        case connections
        case logs
        var id: String { rawValue }

        func title(_ lang: AppLanguage) -> String {
            switch self {
            case .connections: return L10n.t("mac.monitor.connections", lang)
            case .logs: return L10n.t("mac.monitor.logs", lang)
            }
        }

        var systemImage: String {
            switch self {
            case .connections: return "link.circle.fill"
            case .logs: return "text.alignleft"
            }
        }
    }

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 0) {
            MonitorTrafficHeader(
                panel: panel,
                coreAlive: coreAlive,
                lang: lang
            )
            Rectangle().fill(BashXTheme.hairline(for: appearance)).frame(height: 1)

            HStack(spacing: 10) {
                monitorSegmentBar
                Spacer(minLength: 8)
                if segment == .connections {
                    MonitorConnectionsToolbar(
                        monitor: monitor,
                        coreAlive: coreAlive,
                        lang: lang,
                        onCloseAll: onCloseAll
                    )
                } else {
                    MonitorLogsToolbar(monitor: monitor, lang: lang)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(BashXTheme.hairline(for: appearance)).frame(height: 1)

            Group {
                switch segment {
                case .connections:
                    MonitorConnectionsList(monitor: monitor, coreAlive: coreAlive, lang: lang)
                case .logs:
                    MonitorLogsList(monitor: monitor, coreAlive: coreAlive, lang: lang)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .transaction { $0.animation = nil }
    }

    private var monitorSegmentBar: some View {
        HStack(spacing: 3) {
            ForEach(MonitorSegment.allCases) { s in
                let selected = segment == s
                Button {
                    segment = s
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: s.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(s.title(lang))
                            .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .rounded))
                    }
                    .foregroundStyle(selected ? Color.white : BashXTheme.secondaryLabel(for: appearance))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(selected ? BashXTheme.accent(for: appearance) : Color.clear)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.85))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(BashXTheme.hairline(for: appearance), lineWidth: 0.8)
                )
        }
    }
}

// MARK: - Traffic header (only this redraws on 1Hz rates)

private struct MonitorTrafficHeader: View {
    @ObservedObject var panel: PanelRateStore
    var coreAlive: Bool
    var lang: AppLanguage
    @Environment(\.bashxAppearance) private var appearance

    private func t(_ key: String) -> String { L10n.t(key, lang) }
    private var trafficLive: Bool { panel.isLive && coreAlive }
    private var downTint: Color { BashXTheme.accent(for: appearance) }
    private var upTint: Color { Color(red: 0.98, green: 0.58, blue: 0.28) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(downTint.opacity(appearance == .dark ? 0.24 : 0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(downTint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(t("mac.monitor.traffic"))
                        .font(PanelMetrics.heroTitle)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(trafficLive ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
                            .frame(width: 5, height: 5)
                        Text(trafficLive ? t("mac.monitor.live") : t("mac.monitor.offline"))
                            .font(PanelMetrics.micro)
                            .foregroundStyle(trafficLive ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    ratePill(label: "↓", value: panel.downMbps, tint: downTint)
                    ratePill(label: "↑", value: panel.upMbps, tint: upTint)
                }
            }

            TrafficSessionTotalsView(
                panel: panel,
                downTint: downTint,
                upTint: upTint,
                appearance: appearance,
                lang: lang
            )

            TrafficChartView(
                samples: panel.samples,
                downTint: downTint,
                upTint: upTint,
                appearance: appearance,
                live: trafficLive,
                style: .monitor,
                lang: lang
            )
            .frame(height: 110)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .fill(BashXTheme.card(for: appearance).opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                            .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                    )
            }
        }
        .padding(12)
        .transaction { $0.animation = nil }
    }

    private func ratePill(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(PanelMetrics.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(PanelMetrics.monoLarge)
                .monospacedDigit()
                .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
            Text("/s")
                .font(PanelMetrics.micro)
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
        }
    }
}

private struct MonitorConnectionsToolbar: View {
    let monitor: TrafficMonitor
    var coreAlive: Bool
    var lang: AppLanguage
    var onCloseAll: () -> Void
    @Environment(\.bashxAppearance) private var appearance
    @State private var count = 0
    @State private var empty = true

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.t("mac.monitor.count", lang).replacingOccurrences(of: "%@", with: "\(count)"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(BashXTheme.secondaryFill(for: appearance))
                )
            Button(L10n.t("mac.monitor.clearConn", lang)) { onCloseAll() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!coreAlive || empty)
        }
        .onAppear {
            count = monitor.connectionCount
            empty = monitor.connections.isEmpty
        }
        .onReceive(monitor.$connectionCount) { count = $0 }
        .onReceive(monitor.$connections) { empty = $0.isEmpty }
    }
}

private struct MonitorLogsToolbar: View {
    let monitor: TrafficMonitor
    var lang: AppLanguage
    @State private var empty = true

    var body: some View {
        Button(L10n.t("mac.monitor.clearLogs", lang)) { monitor.logLines = [] }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(empty)
            .onAppear { empty = monitor.logLines.isEmpty }
            .onReceive(monitor.$logLines) { empty = $0.isEmpty }
    }
}

private struct MonitorConnectionsList: View {
    let monitor: TrafficMonitor
    var coreAlive: Bool
    var lang: AppLanguage
    @Environment(\.bashxAppearance) private var appearance
    @State private var rows: [ConnectionRow] = []

    var body: some View {
        Group {
            if !coreAlive {
                MonitorEmptyState(
                    icon: "bolt.slash.fill",
                    title: L10n.t("mac.monitor.coreOff", lang),
                    subtitle: L10n.t("mac.monitor.coreOffHint", lang)
                )
            } else if rows.isEmpty {
                MonitorEmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: L10n.t("mac.monitor.noConn", lang),
                    subtitle: L10n.t("mac.monitor.noConnHint", lang)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rows) { row in
                            connectionRow(row)
                                .contextMenu {
                                    Button(L10n.t("mac.monitor.closeConn", lang)) {
                                        Task { await monitor.closeConnection(id: row.id) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear { rows = monitor.connections }
        .onReceive(monitor.$connections) { rows = $0 }
        .transaction { $0.animation = nil }
    }

    private func connectionRow(_ row: ConnectionRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.host)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !row.process.isEmpty {
                        Text(row.process)
                            .lineLimit(1)
                    }
                    Text(row.chain)
                        .lineLimit(1)
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            Spacer(minLength: 4)
            Text("↓\(ByteFormat.size(row.download))  ↑\(ByteFormat.size(row.upload))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BashXTheme.card(for: appearance))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MonitorLogsList: View {
    let monitor: TrafficMonitor
    var coreAlive: Bool
    var lang: AppLanguage
    @Environment(\.bashxAppearance) private var appearance
    @State private var lines: [String] = []

    var body: some View {
        Group {
            if !coreAlive {
                MonitorEmptyState(
                    icon: "bolt.slash.fill",
                    title: L10n.t("mac.monitor.coreOff", lang),
                    subtitle: L10n.t("mac.monitor.logsOffHint", lang)
                )
            } else if lines.isEmpty {
                MonitorEmptyState(
                    icon: "text.badge.plus",
                    title: L10n.t("mac.monitor.waitLogs", lang),
                    subtitle: L10n.t("mac.monitor.waitLogsHint", lang)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(BashXTheme.primaryLabel(for: appearance).opacity(0.88))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .onAppear { lines = monitor.logLines }
        .onReceive(monitor.$logLines) { lines = $0 }
        .transaction { $0.animation = nil }
    }
}

private struct MonitorEmptyState: View {
    @Environment(\.bashxAppearance) private var appearance
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(BashXTheme.accent(for: appearance))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(PanelMetrics.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
