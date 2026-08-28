import SwiftUI

struct MonitorPane: View {
    @ObservedObject var monitor: TrafficMonitor
    @ObservedObject var panel: PanelRateStore
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
    }

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var trafficLive: Bool { panel.isLive && coreAlive }
    private var downTint: Color { BashXTheme.accent(for: appearance) }
    private var upTint: Color { Color(red: 0.98, green: 0.58, blue: 0.28) }

    var body: some View {
        VStack(spacing: 0) {
            trafficHeader
            Rectangle().fill(BashXTheme.hairline(for: appearance)).frame(height: 1)

            HStack {
                Picker("", selection: $segment) {
                    ForEach(MonitorSegment.allCases) { s in
                        Text(s.title(lang)).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                if segment == .connections {
                    Text(t("mac.monitor.count").replacingOccurrences(of: "%@", with: "\(monitor.connectionCount)"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(t("mac.monitor.clearConn")) { onCloseAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!coreAlive || monitor.connections.isEmpty)
                } else {
                    Button(t("mac.monitor.clearLogs")) { monitor.logLines = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(monitor.logLines.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(BashXTheme.hairline(for: appearance)).frame(height: 1)

            Group {
                switch segment {
                case .connections:
                    connectionsList
                case .logs:
                    logsList
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var trafficHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(downTint.opacity(appearance == .dark ? 0.24 : 0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(downTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(t("mac.monitor.traffic"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(trafficLive ? t("mac.monitor.live") : t("mac.monitor.offline"))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(trafficLive ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(ByteFormat.size(panel.downTotal))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(downTint)
                        .monospacedDigit()
                    Text("↑ \(ByteFormat.size(panel.upTotal))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(upTint)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 10) {
                monitorRateCard(
                    title: t("mac.monitor.down"),
                    symbol: "arrow.down.circle.fill",
                    value: panel.downMbps,
                    tint: downTint
                )
                monitorRateCard(
                    title: t("mac.monitor.up"),
                    symbol: "arrow.up.circle.fill",
                    value: panel.upMbps,
                    tint: upTint
                )
            }

            TrafficChartView(
                samples: panel.samples,
                downTint: downTint,
                upTint: upTint,
                appearance: appearance,
                live: trafficLive,
                style: .monitor,
                lang: lang
            )
            .frame(height: 156)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            downTint.opacity(appearance == .dark ? 0.10 : 0.06),
                            upTint.opacity(appearance == .dark ? 0.05 : 0.03),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .transaction { $0.animation = nil }
    }

    private func monitorRateCard(title: String, symbol: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                    Text("/s")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                )
        }
    }

    private var connectionsList: some View {
        Group {
            if !coreAlive {
                emptyState(t("mac.monitor.coreOff"), t("mac.monitor.coreOffHint"))
            } else if monitor.connections.isEmpty {
                emptyState(t("mac.monitor.noConn"), t("mac.monitor.noConnHint"))
            } else {
                List {
                    ForEach(monitor.connections) { row in
                        connectionRow(row)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .contextMenu {
                                Button(t("mac.monitor.closeConn")) {
                                    Task { await monitor.closeConnection(id: row.id) }
                                }
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func connectionRow(_ row: ConnectionRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.host)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !row.network.isEmpty {
                    Text(row.network)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if !row.process.isEmpty {
                    Label(row.process, systemImage: "app.badge")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(row.chain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                    .lineLimit(1)
                Spacer()
                Text("↓\(ByteFormat.size(row.download)) ↑\(ByteFormat.size(row.upload))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(row.rule)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var logsList: some View {
        Group {
            if !coreAlive {
                emptyState(t("mac.monitor.coreOff"), t("mac.monitor.logsOffHint"))
            } else if monitor.logLines.isEmpty {
                emptyState(t("mac.monitor.waitLogs"), t("mac.monitor.waitLogsHint"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(monitor.logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: monitor.logLines.count) { _ in
                        if let last = monitor.logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
