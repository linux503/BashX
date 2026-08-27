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
    case globe
    case portal
    case lock
    case orbit
    case terminal
    case pulse

    /// Default logo for new installs — BashX brand mark.
    static let `default`: LogoStyle = .markX

    /// Phone home-screen set — bold marks that stay clear at 60pt.
    /// First item is primary AppIcon art (`markX` → nil alternate name).
    static let iosCurated: [LogoStyle] = [
        .markX, .ring, .shield, .bolt, .signal, .hex, .globe, .pulse,
    ]

    /// iOS primary home-screen icon art (matches Assets AppIcon + Mac default).
    static let iosPrimary: LogoStyle = .default


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
        case .globe: return "全球"
        case .portal: return "传送门"
        case .lock: return "加密锁"
        case .orbit: return "星轨"
        case .terminal: return "终端"
        case .pulse: return "脉冲"
        }
    }

    var subtitle: String {
        switch self {
        case .markX: return "品牌默认 · 黄底 X"
        case .bolt: return "琥珀棱锥"
        case .ring: return "靛蓝轨道"
        case .signal: return "珊瑚罗盘"
        case .shield: return "海军盾牌"
        case .hex: return "翠绿网格"
        case .nodes: return "紫晶链路"
        case .wave: return "天蓝波形"
        case .globe: return "地球蓝"
        case .portal: return "品红隧道"
        case .lock: return "墨金加密"
        case .orbit: return "星云紫"
        case .terminal: return "终端绿"
        case .pulse: return "玫红脉冲"
        }
    }

    /// Per-style dock/panel palette — each logo has its own color family.
    var palette: LogoStylePalette {
        switch self {
        case .markX:
            // BashX default — solid yellow field, dark X for contrast.
            return .init(
                deep: CGColor(red: 0.92, green: 0.68, blue: 0.04, alpha: 1),
                mid: CGColor(red: 1.0, green: 0.84, blue: 0.12, alpha: 1),
                accent: CGColor(red: 1.0, green: 0.94, blue: 0.38, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.97, blue: 0.62, alpha: 0.55),
                ink: CGColor(red: 0.12, green: 0.10, blue: 0.04, alpha: 1),
                inkSoft: CGColor(red: 0.30, green: 0.22, blue: 0.06, alpha: 1)
            )
        case .bolt:
            return .init( // amber / ember — warm, not teal
                deep: CGColor(red: 0.22, green: 0.06, blue: 0.01, alpha: 1),
                mid: CGColor(red: 0.72, green: 0.32, blue: 0.04, alpha: 1),
                accent: CGColor(red: 1.0, green: 0.72, blue: 0.18, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 0.45),
                ink: CGColor(red: 1.0, green: 0.99, blue: 0.94, alpha: 1),
                inkSoft: CGColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 1)
            )
        case .ring:
            return .init( // violet — distinct from brand teal
                deep: CGColor(red: 0.10, green: 0.04, blue: 0.28, alpha: 1),
                mid: CGColor(red: 0.32, green: 0.16, blue: 0.72, alpha: 1),
                accent: CGColor(red: 0.62, green: 0.48, blue: 1.0, alpha: 1),
                rim: CGColor(red: 0.82, green: 0.74, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.98, green: 0.97, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.84, green: 0.78, blue: 1.0, alpha: 1)
            )
        case .signal:
            return .init( // coral / tomato
                deep: CGColor(red: 0.28, green: 0.04, blue: 0.06, alpha: 1),
                mid: CGColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1),
                accent: CGColor(red: 1.0, green: 0.46, blue: 0.28, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.78, blue: 0.62, alpha: 0.42),
                ink: CGColor(red: 1.0, green: 0.98, blue: 0.96, alpha: 1),
                inkSoft: CGColor(red: 1.0, green: 0.82, blue: 0.70, alpha: 1)
            )
        case .shield:
            return .init( // royal blue
                deep: CGColor(red: 0.02, green: 0.08, blue: 0.32, alpha: 1),
                mid: CGColor(red: 0.08, green: 0.32, blue: 0.78, alpha: 1),
                accent: CGColor(red: 0.32, green: 0.68, blue: 1.0, alpha: 1),
                rim: CGColor(red: 0.62, green: 0.84, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1)
            )
        case .hex:
            return .init( // forest lime
                deep: CGColor(red: 0.02, green: 0.18, blue: 0.08, alpha: 1),
                mid: CGColor(red: 0.08, green: 0.52, blue: 0.22, alpha: 1),
                accent: CGColor(red: 0.42, green: 0.95, blue: 0.38, alpha: 1),
                rim: CGColor(red: 0.65, green: 0.98, blue: 0.55, alpha: 0.42),
                ink: CGColor(red: 0.95, green: 1.0, blue: 0.96, alpha: 1),
                inkSoft: CGColor(red: 0.72, green: 0.98, blue: 0.70, alpha: 1)
            )
        case .nodes:
            return .init( // amethyst / orchid
                deep: CGColor(red: 0.16, green: 0.02, blue: 0.28, alpha: 1),
                mid: CGColor(red: 0.52, green: 0.12, blue: 0.72, alpha: 1),
                accent: CGColor(red: 0.86, green: 0.42, blue: 1.0, alpha: 1),
                rim: CGColor(red: 0.94, green: 0.74, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.99, green: 0.96, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.92, green: 0.76, blue: 1.0, alpha: 1)
            )
        case .wave:
            return .init( // electric cyan (warmer sky, not brand teal)
                deep: CGColor(red: 0.02, green: 0.18, blue: 0.28, alpha: 1),
                mid: CGColor(red: 0.04, green: 0.55, blue: 0.72, alpha: 1),
                accent: CGColor(red: 0.15, green: 0.92, blue: 0.98, alpha: 1),
                rim: CGColor(red: 0.60, green: 0.96, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.94, green: 0.99, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.68, green: 0.95, blue: 1.0, alpha: 1)
            )
        case .globe:
            return .init( // arctic ice — cool cyan, distinct from teal brand
                deep: CGColor(red: 0.02, green: 0.16, blue: 0.34, alpha: 1),
                mid: CGColor(red: 0.06, green: 0.48, blue: 0.78, alpha: 1),
                accent: CGColor(red: 0.35, green: 0.88, blue: 1.0, alpha: 1),
                rim: CGColor(red: 0.70, green: 0.94, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.96, green: 0.99, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.72, green: 0.94, blue: 1.0, alpha: 1)
            )
        case .portal:
            return .init( // hot magenta
                deep: CGColor(red: 0.22, green: 0.02, blue: 0.18, alpha: 1),
                mid: CGColor(red: 0.68, green: 0.08, blue: 0.48, alpha: 1),
                accent: CGColor(red: 1.0, green: 0.28, blue: 0.78, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.70, blue: 0.90, alpha: 0.42),
                ink: CGColor(red: 1.0, green: 0.97, blue: 0.99, alpha: 1),
                inkSoft: CGColor(red: 1.0, green: 0.78, blue: 0.92, alpha: 1)
            )
        case .lock:
            return .init( // graphite + gold
                deep: CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1),
                mid: CGColor(red: 0.32, green: 0.30, blue: 0.28, alpha: 1),
                accent: CGColor(red: 0.96, green: 0.78, blue: 0.22, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.88, blue: 0.48, alpha: 0.42),
                ink: CGColor(red: 0.99, green: 0.97, blue: 0.90, alpha: 1),
                inkSoft: CGColor(red: 0.96, green: 0.86, blue: 0.48, alpha: 1)
            )
        case .orbit:
            return .init( // nebula — deep purple / fuchsia
                deep: CGColor(red: 0.06, green: 0.02, blue: 0.22, alpha: 1),
                mid: CGColor(red: 0.36, green: 0.08, blue: 0.58, alpha: 1),
                accent: CGColor(red: 0.92, green: 0.36, blue: 1.0, alpha: 1),
                rim: CGColor(red: 0.96, green: 0.72, blue: 1.0, alpha: 0.42),
                ink: CGColor(red: 0.99, green: 0.96, blue: 1.0, alpha: 1),
                inkSoft: CGColor(red: 0.92, green: 0.74, blue: 1.0, alpha: 1)
            )
        case .terminal:
            return .init( // matrix green
                deep: CGColor(red: 0.01, green: 0.10, blue: 0.03, alpha: 1),
                mid: CGColor(red: 0.04, green: 0.32, blue: 0.10, alpha: 1),
                accent: CGColor(red: 0.28, green: 1.0, blue: 0.42, alpha: 1),
                rim: CGColor(red: 0.55, green: 1.0, blue: 0.60, alpha: 0.42),
                ink: CGColor(red: 0.82, green: 1.0, blue: 0.86, alpha: 1),
                inkSoft: CGColor(red: 0.48, green: 0.98, blue: 0.55, alpha: 1)
            )
        case .pulse:
            return .init( // rose / candy
                deep: CGColor(red: 0.24, green: 0.02, blue: 0.12, alpha: 1),
                mid: CGColor(red: 0.72, green: 0.10, blue: 0.36, alpha: 1),
                accent: CGColor(red: 1.0, green: 0.38, blue: 0.58, alpha: 1),
                rim: CGColor(red: 1.0, green: 0.72, blue: 0.82, alpha: 0.42),
                ink: CGColor(red: 1.0, green: 0.97, blue: 0.98, alpha: 1),
                inkSoft: CGColor(red: 1.0, green: 0.78, blue: 0.86, alpha: 1)
            )
        }
    }
}

struct LogoStylePalette {
    let deep: CGColor
    let mid: CGColor
    let accent: CGColor
    let rim: CGColor
    let ink: CGColor
    let inkSoft: CGColor
}

enum LogoPalette {
    /// Fallback brand yellow (BashX default).
    static let deep = LogoStyle.markX.palette.deep
    static let slate = LogoStyle.markX.palette.mid
    static let teal = LogoStyle.markX.palette.mid
    static let mint = LogoStyle.markX.palette.accent
    static let ink = LogoStyle.markX.palette.ink
    static let inkSoft = LogoStyle.markX.palette.inkSoft
}

#if canImport(AppKit)
enum LogoRenderer {
    private static let imageCache = NSCache<NSString, NSImage>()

    private static func cacheKey(
        style: LogoStyle,
        pixels: Int,
        colored: Bool,
        panel: Bool,
        dockSafeArea: Bool,
        iosOpaque: Bool = false
    ) -> NSString {
        "\(style.rawValue)|\(pixels)|\(colored ? 1 : 0)|\(panel ? 1 : 0)|\(dockSafeArea ? 1 : 0)|\(iosOpaque ? 1 : 0)" as NSString
    }

    /// Template icon for menu bar — supersampled; Ventura menu bar uses ~18pt.
    static func templateImage(style: LogoStyle, size: CGFloat = 18) -> NSImage {
        let px = max(72, Int((size * 4).rounded()))
        let base = render(style: style, pixels: px, colored: false)
        let image = NSImage(size: NSSize(width: size, height: size))
        if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: size, height: size)
            image.addRepresentation(rep)
        } else if let copy = base.copy() as? NSImage {
            copy.size = NSSize(width: size, height: size)
            return copy
        }
        image.isTemplate = true
        return image
    }

    /// Colored app / dock icon — leaves transparent margin so Dock size matches other apps.
    static func appIcon(style: LogoStyle, pixels: Int = 256) -> NSImage {
        render(style: style, pixels: pixels, colored: true, panel: false, dockSafeArea: true)
    }

    /// iOS App Store / home-screen icon — full-bleed opaque (no alpha; system applies mask).
    static func iosAppIcon(style: LogoStyle, pixels: Int = 1024) -> NSImage {
        render(style: style, pixels: pixels, colored: true, panel: false, dockSafeArea: false, iosOpaque: true)
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
        dockSafeArea: Bool = false,
        iosOpaque: Bool = false
    ) -> NSImage {
        let key = cacheKey(
            style: style, pixels: pixels, colored: colored, panel: panel,
            dockSafeArea: dockSafeArea, iosOpaque: iosOpaque
        )
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
        // macOS Dock: transparent inset. iOS: opaque full-bleed (system applies mask).
        let pad = (!iosOpaque && dockSafeArea) ? canvas * 0.11 : 0
        let s = canvas - pad * 2
        if pad > 0 {
            ctx.translateBy(x: pad, y: pad)
        }

        let menuBar = !colored
        let markScale: CGFloat = iosOpaque ? 1.12 : 1.0
        let markSize = s / markScale
        let markPad = (s - markSize) / 2

        if colored {
            let palette = style.palette
            if iosOpaque {
                drawIOSOpaqueBackground(in: ctx, size: s, palette: palette)
            } else {
                drawColoredBackground(in: ctx, size: s, palette: palette)
            }
            ctx.setStrokeColor(palette.ink)
            ctx.setFillColor(palette.ink)
        } else {
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if iosOpaque && markPad > 0 {
            ctx.saveGState()
            ctx.translateBy(x: markPad, y: markPad)
        }
        let drawS = iosOpaque ? markSize : s
        let inkSoft = colored ? style.palette.inkSoft : nil

        switch style {
        case .markX: drawMarkX(in: ctx, size: drawS, colored: colored, menuBar: menuBar, panel: panel, ink: colored ? style.palette.ink : nil, inkSoft: inkSoft)
        case .bolt: drawBolt(in: ctx, size: drawS, menuBar: menuBar)
        case .ring: drawRing(in: ctx, size: drawS, menuBar: menuBar)
        case .signal: drawSignal(in: ctx, size: drawS, menuBar: menuBar, ink: colored ? style.palette.ink : nil)
        case .shield: drawShield(in: ctx, size: drawS, menuBar: menuBar)
        case .hex: drawHex(in: ctx, size: drawS, menuBar: menuBar)
        case .nodes: drawNodes(in: ctx, size: drawS, menuBar: menuBar)
        case .wave: drawWave(in: ctx, size: drawS, menuBar: menuBar)
        case .globe: drawGlobe(in: ctx, size: drawS, menuBar: menuBar)
        case .portal: drawPortal(in: ctx, size: drawS, menuBar: menuBar)
        case .lock: drawLock(in: ctx, size: drawS, menuBar: menuBar)
        case .orbit: drawOrbit(in: ctx, size: drawS, menuBar: menuBar)
        case .terminal: drawTerminal(in: ctx, size: drawS, menuBar: menuBar)
        case .pulse: drawPulse(in: ctx, size: drawS, menuBar: menuBar)
        }

        if iosOpaque && markPad > 0 {
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        imageCache.setObject(img, forKey: key)
        return img
    }

    private static func drawColoredBackground(in ctx: CGContext, size s: CGFloat, palette: LogoStylePalette) {
        let inset = s * 0.02
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = s * 0.22
        let colors = [palette.deep, palette.mid, palette.accent] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.48, 1]
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
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray
            if let hg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: hi, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    hg,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.midY),
                    options: []
                )
            }
            ctx.restoreGState()
        }
        ctx.setStrokeColor(palette.rim)
        ctx.setLineWidth(max(1, s * 0.014))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    /// Full-bleed opaque fill — iOS forbids alpha on App Icons.
    private static func drawIOSOpaqueBackground(in ctx: CGContext, size s: CGFloat, palette: LogoStylePalette) {
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let colors = [palette.deep, palette.mid, palette.accent] as CFArray
        if let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.45, 1]
        ) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
            let hi = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray
            if let hg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: hi, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    hg,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.midY),
                    options: []
                )
            }
        } else {
            ctx.setFillColor(palette.mid)
            ctx.fill(rect)
        }
    }

    // MARK: - Default mark

    /// BashX brand: bold X on yellow — same mark for menu bar, dock, and iOS.
    private static func drawMarkX(
        in ctx: CGContext,
        size s: CGFloat,
        colored: Bool,
        menuBar: Bool,
        panel: Bool = false,
        ink: CGColor? = nil,
        inkSoft: CGColor? = nil
    ) {
        _ = colored
        _ = ink
        drawBoldX(in: ctx, size: s, menuBar: menuBar, panel: panel, inkSoft: inkSoft)
    }

    private static func drawBoldX(
        in ctx: CGContext,
        size s: CGFloat,
        menuBar: Bool,
        panel: Bool = false,
        inkSoft: CGColor? = nil
    ) {
        let center = CGPoint(x: s * 0.5, y: s * 0.5)
        // Slightly larger + thicker for dock clarity
        let length: CGFloat = menuBar ? s * 0.58 : (panel ? s * 0.56 : s * 0.54)
        let lineWidth: CGFloat = menuBar
            ? max(3.2, s * 0.24)
            : (panel ? max(3.2, s * 0.24) : max(2.8, s * 0.22))
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
        if !menuBar {
            let hub = s * 0.055
            ctx.setFillColor(inkSoft ?? LogoPalette.inkSoft)
            ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
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
        let lw = menuBar ? max(2.8, s * 0.20) : max(2.2, s * 0.12)
        ctx.setLineWidth(lw)
        let inset = menuBar ? s * 0.16 : s * 0.16
        ctx.strokeEllipse(in: CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2))
        if !menuBar {
            ctx.setLineWidth(max(1.8, s * 0.08))
            ctx.strokeEllipse(in: CGRect(x: s * 0.28, y: s * 0.28, width: s * 0.44, height: s * 0.44))
        }
        let r = menuBar ? s * 0.08 : s * 0.075
        ctx.fillEllipse(in: CGRect(x: s * 0.5 - r, y: s * 0.5 - r, width: r * 2, height: r * 2))
    }

    /// Compass rose — ring + N tick + needle (replaces radar).
    private static func drawSignal(in ctx: CGContext, size s: CGFloat, menuBar: Bool, ink: CGColor? = nil) {
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
            ctx.setFillColor(ink ?? LogoPalette.ink)
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

    /// Globe — meridians + equator on a sphere outline.
    private static func drawGlobe(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let c = CGPoint(x: s * 0.50, y: s * 0.50)
        let r = menuBar ? s * 0.38 : s * 0.36
        ctx.setLineWidth(menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.09))
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        // Vertical meridian ellipse
        let merW = r * (menuBar ? 0.52 : 0.58)
        ctx.strokeEllipse(in: CGRect(x: c.x - merW, y: c.y - r * 0.98, width: merW * 2, height: r * 1.96))

        // Equator
        ctx.move(to: CGPoint(x: c.x - r * 0.96, y: c.y))
        ctx.addLine(to: CGPoint(x: c.x + r * 0.96, y: c.y))
        ctx.strokePath()

        if !menuBar {
            // Secondary meridian (tilted)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat.pi / 6)
            ctx.translateBy(x: -c.x, y: -c.y)
            let mer2 = r * 0.42
            ctx.strokeEllipse(in: CGRect(x: c.x - mer2, y: c.y - r * 0.92, width: mer2 * 2, height: r * 1.84))
            ctx.restoreGState()
        }
    }

    /// Portal arch — tunnel gateway silhouette.
    private static func drawPortal(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let lw = menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.095)
        ctx.setLineWidth(lw)
        let left = s * (menuBar ? 0.22 : 0.24)
        let right = s * (menuBar ? 0.78 : 0.76)
        let top = s * (menuBar ? 0.16 : 0.18)
        let base = s * (menuBar ? 0.84 : 0.82)
        let archR = (right - left) / 2

        let frame = CGMutablePath()
        frame.move(to: CGPoint(x: left, y: base))
        frame.addLine(to: CGPoint(x: left, y: top + archR))
        frame.addArc(
            center: CGPoint(x: s * 0.50, y: top + archR),
            radius: archR,
            startAngle: CGFloat.pi,
            endAngle: 0,
            clockwise: false
        )
        frame.addLine(to: CGPoint(x: right, y: base))
        ctx.addPath(frame)
        ctx.strokePath()

        if !menuBar {
            // Inner glow arch
            ctx.setLineWidth(max(1.2, s * 0.065))
            let inset = s * 0.10
            let innerR = archR - inset
            ctx.addArc(
                center: CGPoint(x: s * 0.50, y: top + archR + inset * 0.15),
                radius: innerR,
                startAngle: CGFloat.pi * 1.08,
                endAngle: -CGFloat.pi * 0.08,
                clockwise: false
            )
            ctx.strokePath()
            // Threshold line
            ctx.move(to: CGPoint(x: left + inset * 0.6, y: base - inset * 0.35))
            ctx.addLine(to: CGPoint(x: right - inset * 0.6, y: base - inset * 0.35))
            ctx.strokePath()
        }
    }

    /// Padlock — secure tunnel mark.
    private static func drawLock(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let lw = menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.095)
        ctx.setLineWidth(lw)
        let body = CGRect(x: s * 0.28, y: s * 0.44, width: s * 0.44, height: s * 0.38)
        let shackleR = s * (menuBar ? 0.17 : 0.16)
        let shackleC = CGPoint(x: s * 0.50, y: s * 0.44)

        // Shackle
        ctx.addArc(
            center: shackleC,
            radius: shackleR,
            startAngle: CGFloat.pi,
            endAngle: 0,
            clockwise: false
        )
        ctx.strokePath()

        // Body
        let corner = s * 0.08
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
        if menuBar {
            ctx.fillPath()
        } else {
            ctx.strokePath()
            let hole = s * 0.055
            ctx.fillEllipse(in: CGRect(x: s * 0.50 - hole, y: s * 0.58 - hole, width: hole * 2, height: hole * 2))
            ctx.setLineWidth(max(1.2, s * 0.05))
            ctx.move(to: CGPoint(x: s * 0.50, y: s * 0.58 + hole))
            ctx.addLine(to: CGPoint(x: s * 0.50, y: s * 0.72))
            ctx.strokePath()
        }
    }

    /// Elliptical orbit with satellite dot.
    private static func drawOrbit(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let c = CGPoint(x: s * 0.50, y: s * 0.52)
        let lw = menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.09)
        ctx.setLineWidth(lw)

        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: -CGFloat.pi / 7)
        ctx.translateBy(x: -c.x, y: -c.y)
        let rx = s * (menuBar ? 0.36 : 0.34)
        let ry = s * (menuBar ? 0.22 : 0.20)
        ctx.strokeEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
        ctx.restoreGState()

        // Planet core
        let core = menuBar ? s * 0.10 : s * 0.085
        ctx.fillEllipse(in: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2))

        // Satellite on orbit (~315°)
        let angle = -CGFloat.pi * 0.72
        let satRx = s * 0.34
        let satRy = s * 0.20
        let rot = -CGFloat.pi / 7
        let ox = cos(angle) * satRx
        let oy = sin(angle) * satRy
        let sx = c.x + ox * cos(rot) - oy * sin(rot)
        let sy = c.y + ox * sin(rot) + oy * cos(rot)
        let dot = menuBar ? s * 0.07 : s * 0.06
        ctx.fillEllipse(in: CGRect(x: sx - dot, y: sy - dot, width: dot * 2, height: dot * 2))
    }

    /// Bash terminal prompt — chevron + cursor bar.
    private static func drawTerminal(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let lw = menuBar ? max(2.8, s * 0.18) : max(1.6, s * 0.10)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // `>` chevron
        let tip = CGPoint(x: s * 0.30, y: s * 0.50)
        let top = CGPoint(x: s * 0.48, y: s * 0.32)
        let bot = CGPoint(x: s * 0.48, y: s * 0.68)
        ctx.move(to: top)
        ctx.addLine(to: tip)
        ctx.addLine(to: bot)
        ctx.strokePath()

        // Cursor block or underscore
        if menuBar {
            ctx.move(to: CGPoint(x: s * 0.54, y: s * 0.50))
            ctx.addLine(to: CGPoint(x: s * 0.78, y: s * 0.50))
            ctx.strokePath()
        } else {
            let bar = CGRect(x: s * 0.54, y: s * 0.38, width: s * 0.28, height: s * 0.24)
            ctx.fill(bar)
            // Blink underscore accent
            ctx.setLineWidth(max(1.2, s * 0.06))
            ctx.move(to: CGPoint(x: s * 0.54, y: s * 0.72))
            ctx.addLine(to: CGPoint(x: s * 0.82, y: s * 0.72))
            ctx.strokePath()
        }
    }

    /// Sonar pulse — radiating arcs from center-left.
    private static func drawPulse(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
        let origin = CGPoint(x: s * 0.34, y: s * 0.54)
        let lw = menuBar ? max(2.6, s * 0.16) : max(1.5, s * 0.09)
        ctx.setLineWidth(lw)
        let arcs = menuBar ? 2 : 3
        for i in 0..<arcs {
            let radius = s * (0.16 + CGFloat(i) * (menuBar ? 0.16 : 0.14))
            ctx.addArc(
                center: origin,
                radius: radius,
                startAngle: -CGFloat.pi / 3.2,
                endAngle: CGFloat.pi / 3.2,
                clockwise: false
            )
            ctx.strokePath()
        }
        let hub = menuBar ? s * 0.08 : s * 0.065
        ctx.fillEllipse(in: CGRect(x: origin.x - hub, y: origin.y - hub, width: hub * 2, height: hub * 2))

        if !menuBar {
            // Target dot on outer wave
            let tip = CGPoint(x: origin.x + s * 0.44, y: origin.y - s * 0.06)
            let dot = s * 0.05
            ctx.fillEllipse(in: CGRect(x: tip.x - dot, y: tip.y - dot, width: dot * 2, height: dot * 2))
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

#if !ALT_ICON_GEN
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
    var appearance: AppAppearance = .light
    var onChange: ((LogoStyle) -> Void)?

    private let columns = [
        GridItem(.fixed(52), spacing: 6),
        GridItem(.fixed(52), spacing: 6),
        GridItem(.fixed(52), spacing: 6),
        GridItem(.fixed(52), spacing: 6),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(LogoStyle.allCases) { style in
                Button {
                    selection = style
                    onChange?(style)
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == style
                                      ? BashXTheme.accent(for: appearance).opacity(0.14)
                                      : BashXTheme.secondaryFill(for: appearance))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            selection == style
                                                ? BashXTheme.accent(for: appearance).opacity(0.75)
                                                : BashXTheme.separator(for: appearance),
                                            lineWidth: selection == style ? 1.5 : 0.5
                                        )
                                )
                            LogoIconView(style: style, size: 22, colored: true)
                        }
                        .frame(width: 52, height: 44)

                        Text(style.title)
                            .font(.system(size: 9, weight: selection == style ? .semibold : .regular))
                            .foregroundStyle(
                                selection == style
                                    ? BashXTheme.primaryLabel(for: appearance)
                                    : BashXTheme.secondaryLabel(for: appearance)
                            )
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
#endif
