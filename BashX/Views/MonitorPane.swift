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

        var systemImage: String {
            switch self {
            case .connections: return "link.circle.fill"
            case .logs: return "text.alignleft"
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

            HStack(spacing: 10) {
                monitorSegmentBar

                Spacer(minLength: 8)

                if segment == .connections {
                    Text(t("mac.monitor.count").replacingOccurrences(of: "%@", with: "\(monitor.connectionCount)"))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.secondaryFill(for: appearance))
                        )
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

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

    private var monitorSegmentBar: some View {
        HStack(spacing: 3) {
            ForEach(MonitorSegment.allCases) { s in
                let selected = segment == s
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { segment = s }
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

    private var trafficHeader: some View {
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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(panel.downMbps)/s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(downTint)
                        .monospacedDigit()
                    Text("↑ \(panel.upMbps)/s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(upTint)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
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
            .frame(height: 132)
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
        .background {
            LinearGradient(
                colors: [
                    downTint.opacity(appearance == .dark ? 0.10 : 0.06),
                    upTint.opacity(appearance == .dark ? 0.05 : 0.03),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .transaction { $0.animation = nil }
    }

    private func monitorRateCard(title: String, symbol: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                    Text("/s")
                        .font(PanelMetrics.caption)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
                )
        }
    }

    private var connectionsList: some View {
        Group {
            if !coreAlive {
                emptyState(
                    icon: "bolt.slash.fill",
                    title: t("mac.monitor.coreOff"),
                    subtitle: t("mac.monitor.coreOffHint")
                )
            } else if monitor.connections.isEmpty {
                emptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: t("mac.monitor.noConn"),
                    subtitle: t("mac.monitor.noConnHint")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(monitor.connections) { row in
                            connectionCard(row)
                                .contextMenu {
                                    Button(t("mac.monitor.closeConn")) {
                                        Task { await monitor.closeConnection(id: row.id) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func connectionCard(_ row: ConnectionRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(row.host)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !row.network.isEmpty {
                    Text(row.network.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.accentSoft(for: appearance))
                        )
                }
            }

            HStack(spacing: 8) {
                if !row.process.isEmpty {
                    Label(row.process, systemImage: "app.fill")
                        .font(PanelMetrics.caption)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .lineLimit(1)
                }
                Text(row.chain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("↓\(ByteFormat.size(row.download))  ↑\(ByteFormat.size(row.upload))")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            if !row.rule.isEmpty {
                Text(row.rule)
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private var logsList: some View {
        Group {
            if !coreAlive {
                emptyState(
                    icon: "bolt.slash.fill",
                    title: t("mac.monitor.coreOff"),
                    subtitle: t("mac.monitor.logsOffHint")
                )
            } else if monitor.logLines.isEmpty {
                emptyState(
                    icon: "text.badge.plus",
                    title: t("mac.monitor.waitLogs"),
                    subtitle: t("mac.monitor.waitLogsHint")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(monitor.logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance).opacity(0.88))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(idx % 2 == 0
                                                  ? BashXTheme.card(for: appearance)
                                                  : BashXTheme.secondaryFill(for: appearance).opacity(0.35))
                                    }
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

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(BashXTheme.accentSoft(for: appearance))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }
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
