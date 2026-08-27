import SwiftUI

struct MonitorPane: View {
    @ObservedObject var monitor: TrafficMonitor
    @Binding var segment: MonitorSegment
    var coreRunning: Bool
    var onCloseAll: () -> Void

    enum MonitorSegment: String, CaseIterable, Identifiable {
        case connections = "连接"
        case logs = "日志"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            trafficHeader
            Rectangle().fill(BashXTheme.hairline).frame(height: 1)

            HStack {
                Picker("", selection: $segment) {
                    ForEach(MonitorSegment.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                if segment == .connections {
                    Text("\(monitor.connectionCount) 条")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("清空连接") { onCloseAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!coreRunning || monitor.connections.isEmpty)
                } else {
                    Button("清空日志") { monitor.logLines = [] }
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
                Text("流量")
                    .font(.subheadline.weight(.semibold))
                Text(monitor.isLive && coreRunning ? "实时" : "离线")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                Spacer()
                Text("累计 ↓\(ByteFormat.size(monitor.downTotal)) ↑\(ByteFormat.size(monitor.upTotal))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                monitorRateChip(
                    title: "下载",
                    symbol: "arrow.down.circle.fill",
                    value: ByteFormat.fixedMegaNumber(monitor.downRate),
                    tint: BashXTheme.accent
                )
                monitorRateChip(
                    title: "上传",
                    symbol: "arrow.up.circle.fill",
                    value: ByteFormat.fixedMegaNumber(monitor.upRate),
                    tint: Color(red: 0.95, green: 0.55, blue: 0.18)
                )
                Spacer()
            }

            TrafficSparkline(samples: monitor.samples)
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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                    Text("M/s")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
            if !coreRunning {
                emptyState("内核未运行", "启动内核后可查看连接")
            } else if monitor.connections.isEmpty {
                emptyState("暂无活跃连接", "产生流量后会显示在这里")
            } else {
                List {
                    ForEach(monitor.connections) { row in
                        connectionRow(row)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .contextMenu {
                                Button("关闭此连接") {
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
            if !coreRunning {
                emptyState("内核未运行", "启动内核后可查看连接日志")
            } else if monitor.logLines.isEmpty {
                emptyState("等待日志…", "有请求时会实时滚动显示")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(monitor.logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(14)
                    }
                    .onValueChange(monitor.logLines.count) { _ in
                        if let last = monitor.logLines.indices.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(BashXTheme.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TrafficSparkline: View {
    let samples: [TrafficSample]

    var body: some View {
        GeometryReader { geo in
            let downs = samples.map(\.down)
            let ups = samples.map(\.up)
            let maxV = max(downs.max() ?? 0, ups.max() ?? 0, 1)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BashXTheme.accent.opacity(0.08),
                                Color.primary.opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(BashXTheme.accent.opacity(0.18), lineWidth: 0.5)
                    )

                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.04)).frame(height: 0.5)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                path(values: downs, maxV: maxV, size: geo.size)
                    .fill(
                        LinearGradient(
                            colors: [BashXTheme.accent.opacity(0.35), BashXTheme.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                path(values: downs, maxV: maxV, size: geo.size, closed: false)
                    .stroke(
                        LinearGradient(
                            colors: [BashXTheme.accentGlow, BashXTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: BashXTheme.accent.opacity(0.35), radius: 4, y: 1)

                path(values: ups, maxV: maxV, size: geo.size, closed: false)
                    .stroke(
                        BashXTheme.warn.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 3])
                    )
            }
        }
    }

    private func path(values: [Int64], maxV: Int64, size: CGSize, closed: Bool = true) -> Path {
        Path { p in
            guard values.count > 1 else { return }
            let w = size.width - 16
            let h = size.height - 16
            let step = w / CGFloat(max(values.count - 1, 1))
            for (i, v) in values.enumerated() {
                let x = 8 + CGFloat(i) * step
                let y = 8 + h - CGFloat(Double(v) / Double(maxV)) * h
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            if closed, let last = values.indices.last {
                p.addLine(to: CGPoint(x: 8 + CGFloat(last) * step, y: 8 + h))
                p.addLine(to: CGPoint(x: 8, y: 8 + h))
                p.closeSubpath()
            }
        }
    }
}
