import SwiftUI

/// Dual-series traffic chart — sidebar compact + monitor detail.
struct TrafficChartView: View {
    enum Style {
        case compact
        case monitor
    }

    let samples: [TrafficSample]
    let downTint: Color
    let upTint: Color
    let appearance: AppAppearance
    let live: Bool
    var style: Style = .compact
    var lang: AppLanguage = .current

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var downs: [Int64] { samples.map(\.down) }
    private var ups: [Int64] { samples.map(\.up) }
    private var maxV: Int64 { max(downs.max() ?? 0, ups.max() ?? 0, 1024) }
    private var peakDown: Int64 { downs.max() ?? 0 }
    private var peakUp: Int64 { ups.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .monitor ? 8 : 0) {
            if style == .monitor {
                monitorLegend
            }

            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    chartBackground

                    if live, samples.count > 1 {
                        gridLines
                        seriesLayer(size: geo.size)
                        if style == .monitor {
                            peakBadge
                        }
                    } else {
                        emptyOverlay
                    }
                }
            }
        }
    }

    private var chartBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        downTint.opacity(appearance == .dark ? 0.16 : 0.10),
                        upTint.opacity(appearance == .dark ? 0.08 : 0.04),
                        BashXTheme.secondaryFill(for: appearance).opacity(0.25),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(appearance == .dark ? 0.10 : 0.05), lineWidth: 0.5)
            )
    }

    private var cornerRadius: CGFloat { style == .monitor ? 12 : 10 }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<gridCount, id: \.self) { i in
                if i > 0 {
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(appearance == .dark ? 0.06 : 0.04))
                        .frame(height: 0.5)
                } else {
                    Spacer()
                }
            }
            Spacer()
        }
        .padding(.horizontal, padX)
        .padding(.vertical, padY)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var gridCount: Int { style == .monitor ? 4 : 3 }

    private var padX: CGFloat { style == .monitor ? 10 : 8 }
    private var padY: CGFloat { style == .monitor ? 10 : 8 }

    private func seriesLayer(size: CGSize) -> some View {
        ZStack {
            chartPath(values: downs, maxV: maxV, size: size, closed: true)
                .fill(
                    LinearGradient(
                        colors: [downTint.opacity(style == .monitor ? 0.38 : 0.42), downTint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            if style == .monitor {
                chartPath(values: ups, maxV: maxV, size: size, closed: true)
                    .fill(
                        LinearGradient(
                            colors: [upTint.opacity(0.22), upTint.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            chartPath(values: downs, maxV: maxV, size: size, closed: false)
                .stroke(downTint, style: StrokeStyle(lineWidth: downLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: downTint.opacity(0.35), radius: style == .monitor ? 4 : 3, y: 1)
            chartPath(values: ups, maxV: maxV, size: size, closed: false)
                .stroke(upTint, style: StrokeStyle(lineWidth: upLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: upTint.opacity(0.25), radius: 2, y: 1)
        }
    }

    private var downLineWidth: CGFloat { style == .monitor ? 2.4 : 2.2 }
    private var upLineWidth: CGFloat { style == .monitor ? 2.0 : 1.8 }

    private var emptyOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: live ? "waveform.path.ecg" : "wifi.slash")
                .font(.system(size: style == .monitor ? 22 : 16, weight: .light))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            Text(live ? t("traffic.wait") : t("traffic.needVpn"))
                .font(.system(size: style == .monitor ? 11 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var monitorLegend: some View {
        HStack(spacing: 14) {
            legendDot(color: downTint, title: t("traffic.down"))
            legendDot(color: upTint, title: t("traffic.up"))
            Spacer(minLength: 0)
            if samples.count > 1 {
                Text(t("mac.monitor.peak")
                    .replacingOccurrences(of: "%1", with: ByteFormat.menuBarCompact(peakDown))
                    .replacingOccurrences(of: "%2", with: ByteFormat.menuBarCompact(peakUp)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .monospacedDigit()
            }
        }
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
    }

    private var peakBadge: some View {
        Text(ByteFormat.menuBarCompact(maxV))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(appearance == .dark ? 0.12 : 0.06))
            }
            .padding(padX)
    }

    private func chartPath(values: [Int64], maxV: Int64, size: CGSize, closed: Bool) -> Path {
        Path { p in
            guard values.count > 1 else { return }
            let w = size.width - padX * 2
            let h = size.height - padY * 2
            let step = w / CGFloat(max(values.count - 1, 1))

            func point(at i: Int) -> CGPoint {
                let x = padX + CGFloat(i) * step
                let y = padY + h - CGFloat(Double(values[i]) / Double(maxV)) * h
                return CGPoint(x: x, y: y)
            }

            p.move(to: point(at: 0))
            for i in 1..<values.count {
                let prev = point(at: i - 1)
                let curr = point(at: i)
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                p.addQuadCurve(to: mid, control: prev)
                if i == values.count - 1 {
                    p.addQuadCurve(to: curr, control: curr)
                }
            }

            if closed {
                p.addLine(to: CGPoint(x: padX + CGFloat(values.count - 1) * step, y: padY + h))
                p.addLine(to: CGPoint(x: padX, y: padY + h))
                p.closeSubpath()
            }
        }
    }
}
