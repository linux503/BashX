import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Switchable BashX logo styles (menu bar + panel + dock).
enum LogoStyle: String, CaseIterable, Identifiable, Codable {
    case markX
    case bolt
    case ring
    case signal
    case shield
    case hex
    case nodes
    case wave

    /// Default logo for new installs.
    static let `default`: LogoStyle = .ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markX: return "BashX"
        case .bolt: return "棱锥"
        case .ring: return "轨道环"
        case .signal: return "罗盘"
        case .shield: return "盾牌"
        case .hex: return "六边形"
        case .nodes: return "链路"
        case .wave: return "波形"
        }
    }

    var subtitle: String {
        switch self {
        case .markX: return "粗体 X"
        case .bolt: return "立体路由"
        case .ring: return "环绕连接 · 默认"
        case .signal: return "方位指引 · 新"
        case .shield: return "安全隧道"
        case .hex: return "科技网格"
        case .nodes: return "双环互锁 · 新"
        case .wave: return "流量脉冲"
        }
    }
}

enum LogoPalette {
    // Soft pastel mist — light & airy
    static let slate = CGColor(red: 0.82, green: 0.88, blue: 0.94, alpha: 1)
    static let indigo = CGColor(red: 0.72, green: 0.82, blue: 0.92, alpha: 1)
    static let azure = CGColor(red: 0.78, green: 0.88, blue: 0.96, alpha: 1)
    static let sky = CGColor(red: 0.92, green: 0.96, blue: 0.99, alpha: 1)
    /// Soft ink for marks on light pastel tiles
    static let ink = CGColor(red: 0.42, green: 0.55, blue: 0.68, alpha: 1)
}

#if canImport(AppKit)
enum LogoRenderer {
    private static let imageCache = NSCache<NSString, NSImage>()

    private static func cacheKey(
        style: LogoStyle,
        pixels: Int,
        colored: Bool,
        panel: Bool,
        dockSafeArea: Bool
    ) -> NSString {
        "\(style.rawValue)|\(pixels)|\(colored ? 1 : 0)|\(panel ? 1 : 0)|\(dockSafeArea ? 1 : 0)" as NSString
    }

    /// Template icon for menu bar — 4× supersampled for crisp edges at small sizes.
    static func templateImage(style: LogoStyle, size: CGFloat = 18) -> NSImage {
        let px = max(72, Int((size * 4).rounded()))
        let base = render(style: style, pixels: px, colored: false)
        if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let copy = NSImage(cgImage: cg, size: NSSize(width: size, height: size))
            copy.isTemplate = true
            return copy
        }
        let fallback = base.copy() as? NSImage ?? base
        fallback.isTemplate = true
        fallback.size = NSSize(width: size, height: size)
        return fallback
    }

    /// Colored app / dock icon — leaves transparent margin so Dock size matches other apps.
    static func appIcon(style: LogoStyle, pixels: Int = 256) -> NSImage {
        render(style: style, pixels: pixels, colored: true, panel: false, dockSafeArea: true)
    }

    /// High-res colored icon for panel header (crisper at 28–32 pt).
    static func panelIcon(style: LogoStyle, displaySize: CGFloat) -> NSImage {
        let px = max(96, Int((displaySize * 4).rounded()))
        let base = render(style: style, pixels: px, colored: true, panel: true, dockSafeArea: false)
        if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSImage(cgImage: cg, size: NSSize(width: displaySize, height: displaySize))
        }
        let img = base.copy() as? NSImage ?? base
        img.size = NSSize(width: displaySize, height: displaySize)
        return img
    }

    /// Warm common sizes off the hot path so first click feels instant.
    static func warmCache() {
        Task.detached(priority: .utility) {
            for style in LogoStyle.allCases {
                _ = appIcon(style: style, pixels: 256)
                _ = panelIcon(style: style, displaySize: 28)
                _ = panelIcon(style: style, displaySize: 30)
                _ = templateImage(style: style, size: 16)
            }
        }
    }

    private static func render(
        style: LogoStyle,
        pixels: Int,
        colored: Bool,
        panel: Bool = false,
        dockSafeArea: Bool = false
    ) -> NSImage {
        let key = cacheKey(style: style, pixels: pixels, colored: colored, panel: panel, dockSafeArea: dockSafeArea)
        if let hit = imageCache.object(forKey: key) {
            return hit
        }

        let w = pixels
        let h = pixels
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: NSSize(width: w, height: h))
        }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let canvas = CGFloat(pixels)
        // macOS Dock expects ~10–12% transparent inset; edge-to-edge art looks oversized.
        let pad = dockSafeArea ? canvas * 0.11 : 0
        let s = canvas - pad * 2
        if pad > 0 {
            ctx.translateBy(x: pad, y: pad)
        }

        let menuBar = !colored

        if colored {
            drawColoredBackground(in: ctx, size: s)
            ctx.setStrokeColor(LogoPalette.ink)
            ctx.setFillColor(LogoPalette.ink)
        } else {
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch style {
        case .markX: drawMarkX(in: ctx, size: s, colored: colored, menuBar: menuBar, panel: panel)
        case .bolt: drawBolt(in: ctx, size: s, menuBar: menuBar)
        case .ring: drawRing(in: ctx, size: s, menuBar: menuBar)
        case .signal: drawSignal(in: ctx, size: s, menuBar: menuBar)
        case .shield: drawShield(in: ctx, size: s, menuBar: menuBar)
        case .hex: drawHex(in: ctx, size: s, menuBar: menuBar)
        case .nodes: drawNodes(in: ctx, size: s, menuBar: menuBar)
        case .wave: drawWave(in: ctx, size: s, menuBar: menuBar)
        }

        guard let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        imageCache.setObject(img, forKey: key)
        return img
    }

    private static func drawColoredBackground(in ctx: CGContext, size s: CGFloat) {
        // Inner rounded tile — keep a little breathing room inside the draw box.
        let inset = s * 0.02
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = s * 0.22
        let colors = [LogoPalette.slate, LogoPalette.indigo, LogoPalette.azure, LogoPalette.sky] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.35, 0.72, 1]
        ) {
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
            let hi = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray
            if let hg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: hi, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    hg,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.midY + s * 0.08),
                    options: []
                )
            }
            ctx.restoreGState()
        }
        // Soft rim on pastel tile
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.65, blue: 0.78, alpha: 0.28))
        ctx.setLineWidth(max(1, s * 0.012))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    // MARK: - Default mark

    /// Bold rounded X — maximum legibility at 18–20 pt menu bar.
    private static func drawMarkX(in ctx: CGContext, size s: CGFloat, colored: Bool, menuBar: Bool, panel: Bool = false) {
        if colored, !menuBar {
            drawBoldX(in: ctx, size: s, menuBar: false, panel: panel)
            return
        }
        drawBoldX(in: ctx, size: s, menuBar: menuBar, panel: false)
    }

    private static func drawBoldX(in ctx: CGContext, size s: CGFloat, menuBar: Bool, panel: Bool = false) {
        let center = CGPoint(x: s * 0.5, y: s * 0.5)
        let length: CGFloat = menuBar ? s * 0.58 : (panel ? s * 0.54 : s * 0.50)
        let lineWidth: CGFloat = menuBar
            ? max(3.2, s * 0.24)
            : (panel ? max(3.0, s * 0.22) : max(2.4, s * 0.19))
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle)
            ctx.move(to: CGPoint(x: -length / 2, y: 0))
            ctx.addLine(to: CGPoint(x: length / 2, y: 0))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Prism / diamond mark (replaces bolt).
    private static func drawBolt(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        ctx.setLineWidth(0)
        let path = CGMutablePath()
        // Diamond / prism silhouette
        path.move(to: CGPoint(x: s * 0.50, y: s * 0.14))
        path.addLine(to: CGPoint(x: s * 0.78, y: s * 0.42))
        path.addLine(to: CGPoint(x: s * 0.50, y: s * 0.86))
        path.addLine(to: CGPoint(x: s * 0.22, y: s * 0.42))
        path.closeSubpath()
        ctx.addPath(path)
        if menuBar {
            ctx.fillPath()
        } else {
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            ctx.setLineWidth(max(1.2, s * 0.04))
            ctx.move(to: CGPoint(x: s * 0.50, y: s * 0.14))
            ctx.addLine(to: CGPoint(x: s * 0.50, y: s * 0.86))
            ctx.move(to: CGPoint(x: s * 0.22, y: s * 0.42))
            ctx.addLine(to: CGPoint(x: s * 0.78, y: s * 0.42))
            ctx.strokePath()
        }
    }

    private static func drawRing(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let lw = menuBar ? max(2.8, s * 0.20) : max(1.5, s * 0.095)
        ctx.setLineWidth(lw)
        let inset = menuBar ? s * 0.16 : s * 0.18
        ctx.strokeEllipse(in: CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2))
        if !menuBar {
            ctx.setLineWidth(max(1.2, s * 0.065))
            ctx.strokeEllipse(in: CGRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40))
        }
        let r = menuBar ? s * 0.08 : s * 0.065
        ctx.fillEllipse(in: CGRect(x: s * 0.5 - r, y: s * 0.5 - r, width: r * 2, height: r * 2))
    }

    /// Compass rose — ring + N tick + needle (replaces radar).
    private static func drawSignal(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let c = CGPoint(x: s * 0.50, y: s * 0.50)
        let outer = menuBar ? s * 0.38 : s * 0.36
        ctx.setLineWidth(menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.09))
        ctx.strokeEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))

        // Cardinal ticks (N/E/S/W)
        let tickIn = outer * (menuBar ? 0.62 : 0.70)
        let tickOut = outer * 0.98
        ctx.setLineWidth(menuBar ? max(2.4, s * 0.14) : max(1.4, s * 0.08))
        let angles: [CGFloat] = [-CGFloat.pi / 2, 0, CGFloat.pi / 2, CGFloat.pi]
        for angle in angles {
            ctx.move(to: CGPoint(x: c.x + cos(angle) * tickIn, y: c.y + sin(angle) * tickIn))
            ctx.addLine(to: CGPoint(x: c.x + cos(angle) * tickOut, y: c.y + sin(angle) * tickOut))
        }
        ctx.strokePath()

        // Needle (north-pointing diamond)
        let tip = CGPoint(x: c.x, y: c.y - outer * (menuBar ? 0.72 : 0.68))
        let tail = CGPoint(x: c.x, y: c.y + outer * (menuBar ? 0.42 : 0.38))
        let left = CGPoint(x: c.x - outer * 0.16, y: c.y + outer * 0.06)
        let right = CGPoint(x: c.x + outer * 0.16, y: c.y + outer * 0.06)
        let needle = CGMutablePath()
        needle.move(to: tip)
        needle.addLine(to: right)
        needle.addLine(to: tail)
        needle.addLine(to: left)
        needle.closeSubpath()
        ctx.addPath(needle)
        ctx.fillPath()

        let hub = menuBar ? s * 0.07 : s * 0.055
        // Cut hub hole for definition on colored icons
        if !menuBar {
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: c.x - hub, y: c.y - hub, width: hub * 2, height: hub * 2))
            ctx.setBlendMode(.normal)
            ctx.setFillColor(LogoPalette.ink)
        }
        ctx.fillEllipse(in: CGRect(x: c.x - hub * 0.55, y: c.y - hub * 0.55, width: hub * 1.1, height: hub * 1.1))
    }

    private static func drawShield(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        ctx.setLineWidth(menuBar ? max(2.4, s * 0.16) : max(1.5, s * 0.095))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: s * 0.5, y: s * 0.12))
        path.addLine(to: CGPoint(x: s * 0.80, y: s * 0.26))
        path.addLine(to: CGPoint(x: s * 0.80, y: s * 0.50))
        path.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.88), control: CGPoint(x: s * 0.80, y: s * 0.76))
        path.addQuadCurve(to: CGPoint(x: s * 0.20, y: s * 0.50), control: CGPoint(x: s * 0.20, y: s * 0.76))
        path.addLine(to: CGPoint(x: s * 0.20, y: s * 0.26))
        path.closeSubpath()
        ctx.addPath(path)
        if menuBar {
            ctx.fillPath()
        } else {
            ctx.strokePath()
            ctx.setLineWidth(max(1.6, s * 0.105))
            ctx.move(to: CGPoint(x: s * 0.36, y: s * 0.50))
            ctx.addLine(to: CGPoint(x: s * 0.46, y: s * 0.60))
            ctx.addLine(to: CGPoint(x: s * 0.66, y: s * 0.38))
            ctx.strokePath()
        }
    }

    private static func drawHex(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        ctx.setLineWidth(menuBar ? max(2.6, s * 0.18) : max(1.5, s * 0.095))
        let c = CGPoint(x: s * 0.5, y: s * 0.5)
        let r = menuBar ? s * 0.38 : s * 0.34
        let path = hexPath(center: c, radius: r)
        ctx.addPath(path)
        ctx.strokePath()

        if !menuBar {
            ctx.setLineWidth(max(1.4, s * 0.10))
            let pad = s * 0.36
            ctx.move(to: CGPoint(x: pad, y: pad))
            ctx.addLine(to: CGPoint(x: s - pad, y: s - pad))
            ctx.move(to: CGPoint(x: s - pad, y: pad))
            ctx.addLine(to: CGPoint(x: pad, y: s - pad))
            ctx.strokePath()
        }
    }

    /// Interlocking chain links (replaces star node mesh).
    private static func drawNodes(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let lw = menuBar ? max(2.8, s * 0.18) : max(1.7, s * 0.10)
        ctx.setLineWidth(lw)

        // Left link (vertical oval)
        let left = CGRect(x: s * 0.16, y: s * 0.22, width: s * 0.36, height: s * 0.56)
        // Right link (horizontal oval, overlapping)
        let right = CGRect(x: s * 0.40, y: s * 0.34, width: s * 0.44, height: s * 0.32)

        if menuBar {
            // Simplified: two overlapping rings for small size
            let a = CGRect(x: s * 0.12, y: s * 0.28, width: s * 0.44, height: s * 0.44)
            let b = CGRect(x: s * 0.44, y: s * 0.28, width: s * 0.44, height: s * 0.44)
            ctx.strokeEllipse(in: a)
            ctx.strokeEllipse(in: b)
        } else {
            ctx.strokeEllipse(in: left)
            ctx.strokeEllipse(in: right)
            // Center join accent
            let join = s * 0.055
            ctx.fillEllipse(in: CGRect(x: s * 0.50 - join, y: s * 0.50 - join, width: join * 2, height: join * 2))
        }
    }

    private static func drawWave(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        ctx.setLineWidth(menuBar ? max(2.6, s * 0.18) : max(1.5, s * 0.095))
        let lines = menuBar ? 2 : 3
        for i in 0..<lines {
            let y = s * (0.34 + CGFloat(i) * (menuBar ? 0.22 : 0.18))
            let amp = s * (menuBar ? 0.08 : (0.09 - CGFloat(i) * 0.012))
            let path = CGMutablePath()
            path.move(to: CGPoint(x: s * 0.14, y: y))
            path.addCurve(
                to: CGPoint(x: s * 0.50, y: y),
                control1: CGPoint(x: s * 0.26, y: y - amp),
                control2: CGPoint(x: s * 0.38, y: y + amp)
            )
            path.addCurve(
                to: CGPoint(x: s * 0.86, y: y),
                control1: CGPoint(x: s * 0.62, y: y - amp),
                control2: CGPoint(x: s * 0.74, y: y + amp)
            )
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func hexPath(center c: CGPoint, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat.pi / 6 + CGFloat(i) * CGFloat.pi / 3
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - SwiftUI

struct LogoIconView: View {
    let style: LogoStyle
    var size: CGFloat = 18
    var colored: Bool = false
    /// Panel header: 5× supersample + bolder mark.
    var panel: Bool = false

    var body: some View {
        Image(nsImage: iconImage)
            .renderingMode(colored ? .original : .template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private var iconImage: NSImage {
        if colored {
            if panel {
                return LogoRenderer.panelIcon(style: style, displaySize: size)
            }
            return LogoRenderer.appIcon(style: style, pixels: max(96, Int(size * 4)))
        }
        return LogoRenderer.templateImage(style: style, size: size)
    }
}

struct LogoStylePicker: View {
    @Binding var selection: LogoStyle
    var onChange: ((LogoStyle) -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(LogoStyle.allCases) { style in
                Button {
                    selection = style
                    onChange?(style)
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == style
                                      ? LinearGradient(
                                        colors: [BashXTheme.accent.opacity(0.18), BashXTheme.accentSoft.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                      )
                                      : LinearGradient(
                                        colors: [BashXTheme.secondaryFill, BashXTheme.secondaryFill],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      ))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            selection == style ? BashXTheme.accent.opacity(0.6) : BashXTheme.separator,
                                            lineWidth: selection == style ? 1.5 : 0.5
                                        )
                                )
                            LogoIconView(style: style, size: 30, colored: true)
                                .shadow(color: selection == style ? BashXTheme.accent.opacity(0.25) : .clear, radius: 6, y: 2)
                        }
                        .frame(height: 58)

                        Text(style.title)
                            .font(.caption2.weight(selection == style ? .semibold : .regular))
                            .foregroundStyle(selection == style ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help(style.subtitle)
            }
        }
    }
}
#endif
