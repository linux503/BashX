import SwiftUI

struct IOSTrafficChart: View {
    let samples: [TrafficSample]
    let uploadRate: Int64
    let downloadRate: Int64
    var uploadTotal: Int64 = 0
    var downloadTotal: Int64 = 0
    var isLive: Bool
    var duration: TimeInterval = 0

    private var peakRate: Int64 {
        max(samples.map(\.down).max() ?? 0, samples.map(\.up).max() ?? 0, downloadRate, uploadRate, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            chartWell
                .frame(height: 132)
                .padding(.horizontal, 12)

            footer
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("实时流量")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    if isLive {
                        LiveBadge()
                    }
                }
                if isLive {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("已连接 \(IOSTheme.formatDuration(duration)) · 峰 \(ByteFormat.compactRate(peakRate))/s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("连接 VPN 后显示")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if isLive {
                HStack(spacing: 8) {
                    rateChip(value: downloadRate, color: IOSTheme.chartDown, icon: "arrow.down")
                    rateChip(value: uploadRate, color: IOSTheme.chartUp, icon: "arrow.up")
                }
            }
        }
    }

    private var chartWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.13, blue: 0.15),
                            Color(red: 0.05, green: 0.16, blue: 0.18),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if samples.count > 1 {
                TrafficSparkline(samples: samples, peak: peakRate)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            } else {
                Text(isLive ? "等待流量…" : "暂无数据")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private var footer: some View {
        HStack {
            if isLive {
                Text("↓ \(ByteFormat.size(downloadTotal))   ↑ \(ByteFormat.size(uploadTotal))")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                legend("下行", IOSTheme.chartDown)
                legend("上行", IOSTheme.chartUp)
            }
        }
    }

    private func rateChip(value: Int64, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(ByteFormat.compactRate(value) + "/s")
                .font(.caption2.monospacedDigit().weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(IOSTheme.good)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 1 : 0.45)
            Text("LIVE")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(IOSTheme.good)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(IOSTheme.good.opacity(0.12)))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct TrafficSparkline: View {
    let samples: [TrafficSample]
    let peak: Int64

    var body: some View {
        GeometryReader { geo in
            let downs = samples.map(\.down)
            let ups = samples.map(\.up)
            let maxV = max(peak, 1)
            ZStack {
                grid(in: geo.size)
                smoothArea(values: downs, maxV: maxV, size: geo.size, colors: [
                    IOSTheme.chartDown.opacity(0.5),
                    IOSTheme.chartDown.opacity(0.05),
                    Color.clear,
                ])
                smoothLine(values: downs, maxV: maxV, size: geo.size, color: IOSTheme.chartDown, width: 2.2)
                tipDot(values: downs, maxV: maxV, size: geo.size, color: IOSTheme.chartDown)

                smoothArea(values: ups, maxV: maxV, size: geo.size, colors: [
                    IOSTheme.chartUp.opacity(0.28),
                    Color.clear,
                ])
                smoothLine(values: ups, maxV: maxV, size: geo.size, color: IOSTheme.chartUp, width: 1.8, dashed: true)
            }
        }
    }

    private func grid(in size: CGSize) -> some View {
        Canvas { ctx, sz in
            for i in 1..<3 {
                let y = sz.height * CGFloat(i) / 3
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func tipDot(values: [Int64], maxV: Int64, size: CGSize, color: Color) -> some View {
        if let last = values.indices.last, values.count > 1 {
            let pt = point(at: last, values: values, maxV: maxV, size: size)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 4)
                .position(pt)
        }
    }

    private func smoothArea(values: [Int64], maxV: Int64, size: CGSize, colors: [Color]) -> some View {
        smoothPath(values: values, maxV: maxV, size: size, closed: true)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }

    private func smoothLine(
        values: [Int64],
        maxV: Int64,
        size: CGSize,
        color: Color,
        width: CGFloat,
        dashed: Bool = false
    ) -> some View {
        smoothPath(values: values, maxV: maxV, size: size, closed: false)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: width,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dashed ? [4, 3] : []
                )
            )
            .shadow(color: color.opacity(dashed ? 0.1 : 0.35), radius: 4)
    }

    private func point(at i: Int, values: [Int64], maxV: Int64, size: CGSize) -> CGPoint {
        let pad: CGFloat = 2
        let w = size.width - pad * 2
        let h = size.height - pad * 2
        let step = w / CGFloat(max(values.count - 1, 1))
        let x = pad + CGFloat(i) * step
        let y = pad + h - CGFloat(Double(values[i]) / Double(maxV)) * h * 0.9
        return CGPoint(x: x, y: y)
    }

    private func smoothPath(values: [Int64], maxV: Int64, size: CGSize, closed: Bool) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            let pts = values.indices.map { point(at: $0, values: values, maxV: maxV, size: size) }
            path.move(to: pts[0])
            if pts.count == 2 {
                path.addLine(to: pts[1])
            } else {
                for i in 0..<(pts.count - 1) {
                    let p0 = pts[max(0, i - 1)]
                    let p1 = pts[i]
                    let p2 = pts[i + 1]
                    let p3 = pts[min(pts.count - 1, i + 2)]
                    let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                    let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                    path.addCurve(to: p2, control1: c1, control2: c2)
                }
            }
            if closed, let last = pts.last, let first = pts.first {
                let pad: CGFloat = 2
                path.addLine(to: CGPoint(x: last.x, y: size.height - pad))
                path.addLine(to: CGPoint(x: first.x, y: size.height - pad))
                path.closeSubpath()
            }
        }
    }
}
