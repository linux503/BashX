import SwiftUI

struct MonitorPane: View {
    @ObservedObject var monitor: TrafficMonitor
    @ObservedObject var panel: PanelRateStore
    @Binding var segment: MonitorSegment
    var coreAlive: Bool
    var lang: AppLanguage
    var onCloseAll: () -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            trafficHeader
            Rectangle().fill(BashXTheme.hairline).frame(height: 1)

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

            Rectangle().fill(BashXTheme.hairline).frame(height: 1)

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
            HStack {
                Text(t("mac.monitor.traffic"))
                    .font(.subheadline.weight(.semibold))
                Text(trafficLive ? t("mac.monitor.live") : t("mac.monitor.offline"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                Spacer()
                Text("↓\(ByteFormat.size(panel.downTotal)) ↑\(ByteFormat.size(panel.upTotal))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                monitorRateChip(
                    title: t("mac.monitor.down"),
                    symbol: "arrow.down.circle.fill",
                    value: panel.downMbps,
                    tint: BashXTheme.accent
                )
                monitorRateChip(
                    title: t("mac.monitor.up"),
                    symbol: "arrow.up.circle.fill",
                    value: panel.upMbps,
                    tint: Color(red: 0.95, green: 0.55, blue: 0.18)
                )
                Spacer()
            }

            TrafficSparkline(samples: panel.samples)
                .frame(height: 128)
        }
        .padding(16)
        .background {
            LinearGradient(
                colors: [
                    BashXTheme.accent.opacity(0.06),
                    BashXTheme.accentGlow.opacity(0.03),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func monitorRateChip(title: String, symbol: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(value)/s")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.12), tint.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.20), lineWidth: 0.5)
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
                    .foregroundStyle(BashXTheme.accent)
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

// MARK: - Sparkline

private struct TrafficSparkline: View {
    let samples: [TrafficSample]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if samples.count < 2 {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                let maxVal = max(
                    samples.map { Double($0.down + $0.up) }.max() ?? 1,
                    1024
                )
                ZStack(alignment: .bottom) {
                    sparkPath(samples: samples, w: w, h: h, maxVal: maxVal, keyPath: \.down)
                        .stroke(BashXTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    sparkPath(samples: samples, w: w, h: h, maxVal: maxVal, keyPath: \.up)
                        .stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func sparkPath(
        samples: [TrafficSample],
        w: CGFloat,
        h: CGFloat,
        maxVal: Double,
        keyPath: KeyPath<TrafficSample, Int64>
    ) -> Path {
        var path = Path()
        let count = samples.count
        for (i, sample) in samples.enumerated() {
            let x = w * CGFloat(i) / CGFloat(max(count - 1, 1))
            let v = Double(sample[keyPath: keyPath])
            let y = h - CGFloat(v / maxVal) * h * 0.92
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
