#!/usr/bin/swift
// Generate BashX menu-bar (template) + macOS app icons + iOS app icon.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()

// MARK: - macOS menu bar + dock icons (high-contrast dark teal + white X)

func drawAppMark(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if !menuBar {
        let inset = s * 0.04
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let colors = [
            CGColor(red: 0.06, green: 0.10, blue: 0.16, alpha: 1),
            CGColor(red: 0.08, green: 0.18, blue: 0.28, alpha: 1),
            CGColor(red: 0.04, green: 0.48, blue: 0.52, alpha: 1),
            CGColor(red: 0.12, green: 0.72, blue: 0.58, alpha: 1),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.72, 1]) {
            let p = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
            ctx.restoreGState()
        }
        // Soft mint rim
        ctx.setStrokeColor(CGColor(red: 0.45, green: 0.90, blue: 0.78, alpha: 0.40))
        ctx.setLineWidth(max(1, s * 0.014))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
    } else {
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
    }

    // Bold rounded X — primary mark
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let length = menuBar ? s * 0.56 : s * 0.52
    let lw = menuBar ? max(2.8, s * 0.22) : max(2.4, s * 0.20)
    ctx.setLineWidth(lw)
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
        ctx.setFillColor(CGColor(red: 0.72, green: 0.96, blue: 0.88, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    }
}

func renderPNG(pixels: Int, menuBar: Bool) -> Data? {
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    // Dock safe inset (~11%) so icon doesn't look oversized vs system apps
    let canvas = CGFloat(pixels)
    if !menuBar {
        let pad = canvas * 0.11
        ctx.translateBy(x: pad, y: pad)
        drawAppMark(in: ctx, size: canvas - pad * 2, menuBar: false)
    } else {
        drawAppMark(in: ctx, size: canvas, menuBar: true)
    }

    guard let cg = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}

// MARK: - iOS app icon (full-bleed, filled shapes — no stroke halos / transparent corners)

private func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

private func fillGradient(in ctx: CGContext, rect: CGRect, colors: [CGColor], locations: [CGFloat]) {
    guard let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    ) else { return }
    ctx.saveGState()
    ctx.addRect(rect)
    ctx.clip()
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
    )
    ctx.restoreGState()
}

/// Donut ring via even-odd fill — avoids dark anti-aliasing from stroked ellipses.
private func fillRing(in ctx: CGContext, center: CGPoint, outer: CGFloat, inner: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
    path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath(using: .evenOdd)
}

private func fillRadialGradient(
    in ctx: CGContext,
    rect: CGRect,
    center: CGPoint,
    radius: CGFloat,
    colors: [CGColor],
    locations: [CGFloat]
) {
    guard let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    ) else { return }
    ctx.saveGState()
    ctx.addRect(rect)
    ctx.clip()
    ctx.drawRadialGradient(
        grad,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
    ctx.restoreGState()
}

private func drawIOSAppIcon(in ctx: CGContext, size s: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: s, height: s)
    let center = CGPoint(x: s * 0.5, y: s * 0.498)

    // Dark graphite background — neutral slate with subtle blue depth
    fillRadialGradient(
        in: ctx,
        rect: full,
        center: CGPoint(x: s * 0.34, y: s * 0.26),
        radius: s * 0.88,
        colors: [
            cgColor(0.10, 0.11, 0.14),   // #1A1C24
            cgColor(0.14, 0.15, 0.20),   // #242633
            cgColor(0.11, 0.14, 0.19),   // #1C2430
        ],
        locations: [0, 0.52, 1]
    )
    fillGradient(
        in: ctx,
        rect: full,
        colors: [
            cgColor(0.08, 0.22, 0.18, 0.0),
            cgColor(0.05, 0.16, 0.14, 0.70),
        ],
        locations: [0.25, 1]
    )
    // Emerald glow behind mark
    fillRadialGradient(
        in: ctx,
        rect: full,
        center: center,
        radius: s * 0.42,
        colors: [
            cgColor(0.16, 0.82, 0.56, 0.30),
            cgColor(0.16, 0.82, 0.56, 0.0),
        ],
        locations: [0, 1]
    )

    // Mint → emerald mark
    let markColors = [
        cgColor(0.86, 1.00, 0.94),   // #DCFFEF
        cgColor(0.26, 0.88, 0.62),   // #42E09E
        cgColor(0.02, 0.59, 0.41),   // #059669
    ] as CFArray
    let markGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: markColors,
        locations: [0, 0.46, 1]
    )!

    // Rounded "X" — larger mark
    let barLen = s * 0.60
    let barW = s * 0.142
    let corner = barW * 0.45

    func drawBar(angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let barRect = CGRect(x: -barLen / 2, y: -barW / 2, width: barLen, height: barW)
        let path = CGPath(roundedRect: barRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(
            markGrad,
            start: CGPoint(x: -barLen / 2, y: -barW * 0.12),
            end: CGPoint(x: barLen / 2, y: barW * 0.12),
            options: []
        )
        ctx.restoreGState()
    }

    drawBar(angle: .pi / 4)
    drawBar(angle: -.pi / 4)

    // Center hub
    let hubR = s * 0.082
    ctx.setFillColor(cgColor(0.95, 1.0, 0.98))
    ctx.fillEllipse(in: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2))
    ctx.setFillColor(cgColor(0.06, 0.72, 0.51))
    ctx.fillEllipse(in: CGRect(x: center.x - hubR * 0.48, y: center.y - hubR * 0.48, width: hubR * 0.96, height: hubR * 0.96))

    // Accent nodes — warm amber (complementary)
    let amber = cgColor(1.0, 0.72, 0.32)
    let peach = cgColor(1.0, 0.55, 0.38)
    let nodes: [(CGPoint, CGColor, CGFloat)] = [
        (CGPoint(x: s * 0.18, y: s * 0.80), amber, 0.032),
        (CGPoint(x: s * 0.50, y: s * 0.88), peach, 0.028),
        (CGPoint(x: s * 0.82, y: s * 0.78), amber, 0.032),
    ]
    for (pt, color, rScale) in nodes {
        let r = s * rScale
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
    }
}

func renderIOSPNG(pixels: Int) -> Data? {
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // Opaque base matches gradient corner color.
    ctx.setFillColor(cgColor(0.11, 0.14, 0.19))
    ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    drawIOSAppIcon(in: ctx, size: CGFloat(pixels))

    guard let cg = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}

func savePNG(pixels: Int, menuBar: Bool, to url: URL) {
    guard let data = renderPNG(pixels: pixels, menuBar: menuBar) else {
        fputs("Failed to render \(url.path)\n", stderr)
        exit(1)
    }
    try! data.write(to: url)
}

func saveIOSPNG(pixels: Int, to url: URL) {
    guard let data = renderIOSPNG(pixels: pixels) else {
        fputs("Failed to render iOS icon \(url.path)\n", stderr)
        exit(1)
    }
    try! data.write(to: url)
}

let assets = root.appendingPathComponent("BashX/Assets.xcassets")
let appIconDir = assets.appendingPathComponent("AppIcon.appiconset")
let menuDir = assets.appendingPathComponent("MenuBarIcon.imageset")

// macOS App Icon — all Ventura / Finder / Dock sizes
let appSizes: [(String, Int, Bool)] = [
    ("app_16.png", 16, false), ("app_16@2x.png", 32, false),
    ("app_32.png", 32, false), ("app_32@2x.png", 64, false),
    ("app_128.png", 128, false), ("app_128@2x.png", 256, false),
    ("app_256.png", 256, false), ("app_256@2x.png", 512, false),
    ("app_512.png", 512, false), ("app_512@2x.png", 1024, false),
]
for (name, px, menuBar) in appSizes {
    savePNG(pixels: px, menuBar: menuBar, to: appIconDir.appendingPathComponent(name))
}

// Legacy large previews (Settings / About)
savePNG(pixels: 256, menuBar: false, to: appIconDir.appendingPathComponent("icon_256x256.png"))
savePNG(pixels: 512, menuBar: false, to: appIconDir.appendingPathComponent("icon_512x512.png"))
savePNG(pixels: 1024, menuBar: false, to: appIconDir.appendingPathComponent("icon_1024x1024.png"))

// Menu bar template — Ventura 16pt / 32px @2x
savePNG(pixels: 16, menuBar: true, to: menuDir.appendingPathComponent("icon_16.png"))
savePNG(pixels: 32, menuBar: true, to: menuDir.appendingPathComponent("icon_16@2x.png"))
savePNG(pixels: 36, menuBar: true, to: menuDir.appendingPathComponent("icon.png"))

let iosAssets = root.appendingPathComponent("BashXiOS/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iosAssets, withIntermediateDirectories: true)
saveIOSPNG(pixels: 1024, to: iosAssets.appendingPathComponent("AppIcon-1024.png"))
print("Icons written to \(assets.path) and \(iosAssets.path)")
