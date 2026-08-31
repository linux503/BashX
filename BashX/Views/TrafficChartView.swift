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
    private var currentDown: Int64 { samples.last?.down ?? 0 }
    private var currentUp: Int64 { samples.last?.up ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .monitor ? 8 : 0) {
            if style == .monitor {
                monitorLegend
            }

            GeometryReader { geo in
                ZStack {
                    chartBackground

                    if live, samples.count > 1 {
                        gridLines
                        seriesLayer(size: geo.size)
                        if style == .monitor {
                            peakBadge
                        } else {
                            compactRateOverlay
                        }
                        endpointDots(size: geo.size)
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
                        downTint.opacity(appearance == .dark ? 0.14 : 0.08),
                        BashXTheme.secondaryFill(for: appearance).opacity(0.35),
                        upTint.opacity(appearance == .dark ? 0.06 : 0.03),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cornerRadius: CGFloat { style == .monitor ? 12 : 10 }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<gridCount, id: \.self) { i in
                if i > 0 {
                    Spacer()
                    Rectangle()
                        .fill(Color.primary.opacity(appearance == .dark ? 0.05 : 0.035))
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
                        colors: [downTint.opacity(style == .monitor ? 0.36 : 0.30), downTint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            chartPath(values: ups, maxV: maxV, size: size, closed: true)
                .fill(
                    LinearGradient(
                        colors: [upTint.opacity(style == .monitor ? 0.20 : 0.14), upTint.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            chartPath(values: downs, maxV: maxV, size: size, closed: false)
                .stroke(downTint, style: StrokeStyle(lineWidth: downLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: downTint.opacity(0.30), radius: style == .monitor ? 4 : 2, y: 1)
            chartPath(values: ups, maxV: maxV, size: size, closed: false)
                .stroke(upTint, style: StrokeStyle(lineWidth: upLineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: upTint.opacity(0.22), radius: 2, y: 1)
        }
    }

    private var downLineWidth: CGFloat { style == .monitor ? 2.4 : 2.0 }
    private var upLineWidth: CGFloat { style == .monitor ? 2.0 : 1.7 }

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
            legendDot(color: downTint, title: t("traffic.down"), value: ByteFormat.menuBarCompact(currentDown))
            legendDot(color: upTint, title: t("traffic.up"), value: ByteFormat.menuBarCompact(currentUp))
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

    private func legendDot(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            Text("\(value)/s")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private var compactRateOverlay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("↓\(ByteFormat.menuBarCompact(currentDown))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(downTint)
            Text("↑\(ByteFormat.menuBarCompact(currentUp))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(upTint)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func endpointDots(size: CGSize) -> some View {
        let downPt = chartPoint(values: downs, maxV: maxV, size: size, index: downs.count - 1)
        let upPt = chartPoint(values: ups, maxV: maxV, size: size, index: ups.count - 1)
        return ZStack {
            Circle()
                .fill(downTint.opacity(0.25))
                .frame(width: 10, height: 10)
                .position(downPt)
            Circle()
                .fill(downTint)
                .frame(width: 5, height: 5)
                .position(downPt)
            Circle()
                .fill(upTint.opacity(0.22))
                .frame(width: 8, height: 8)
                .position(upPt)
            Circle()
                .fill(upTint)
                .frame(width: 4, height: 4)
                .position(upPt)
        }
        .allowsHitTesting(false)
    }

    private func chartPoint(values: [Int64], maxV: Int64, size: CGSize, index: Int) -> CGPoint {
        guard !values.isEmpty else { return .zero }
        let w = size.width - padX * 2
        let h = size.height - padY * 2
        let step = w / CGFloat(max(values.count - 1, 1))
        let i = min(max(index, 0), values.count - 1)
        let x = padX + CGFloat(i) * step
        let y = padY + h - CGFloat(Double(values[i]) / Double(maxV)) * h
        return CGPoint(x: x, y: y)
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

/// Cumulative traffic row — double-click resets session counters.
struct TrafficSessionTotalsView: View {
    @ObservedObject var panel: PanelRateStore
    let downTint: Color
    let upTint: Color
    let appearance: AppAppearance
    var lang: AppLanguage = .current
    var compact: Bool = false

    @State private var flashReset = false

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 4) {
                Image(systemName: "sum")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                Text(t("traffic.total"))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            HStack(spacing: compact ? 6 : 10) {
                Text("↓ \(ByteFormat.size(panel.sessionDownTotal))")
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(downTint)
                    .monospacedDigit()
                Text("↑ \(ByteFormat.size(panel.sessionUpTotal))")
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(upTint)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if !compact {
                Text(t("traffic.totalHint"))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }
        }
        .padding(.horizontal, compact ? 0 : 12)
        .padding(.vertical, compact ? 0 : 8)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(flashReset
                          ? BashXTheme.accentSoft(for: appearance)
                          : BashXTheme.secondaryFill(for: appearance).opacity(0.55))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            panel.resetSessionTotals()
            withAnimation(.easeOut(duration: 0.2)) { flashReset = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.25)) { flashReset = false }
            }
        }
        .help(t("traffic.totalHint"))
    }
}
