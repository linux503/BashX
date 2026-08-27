#!/usr/bin/swift
// Generate BashX menu-bar (template) + macOS app icons + iOS app icon.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()

// MARK: - macOS menu bar + dock icons (legacy orbit ring)

func drawRing(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if !menuBar {
        let inset = s * 0.05
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let colors = [
            CGColor(red: 0.07, green: 0.13, blue: 0.20, alpha: 1),
            CGColor(red: 0.04, green: 0.52, blue: 0.58, alpha: 1),
            CGColor(red: 0.05, green: 0.68, blue: 0.52, alpha: 1),
            CGColor(red: 0.22, green: 0.88, blue: 0.68, alpha: 1),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.72, 1]) {
            let p = CGPath(roundedRect: rect, cornerWidth: s * 0.24, cornerHeight: s * 0.24, transform: nil)
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
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
    } else {
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
    }

    let lw = menuBar ? max(2.8, s * 0.20) : max(1.5, s * 0.095)
    ctx.setLineWidth(lw)
    let ringInset = menuBar ? s * 0.16 : s * 0.18
    ctx.strokeEllipse(in: CGRect(x: ringInset, y: ringInset, width: s - ringInset * 2, height: s - ringInset * 2))
    if !menuBar {
        ctx.setLineWidth(max(1.2, s * 0.065))
        ctx.strokeEllipse(in: CGRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40))
    }
    let r = menuBar ? s * 0.08 : s * 0.065
    ctx.fillEllipse(in: CGRect(x: s * 0.5 - r, y: s * 0.5 - r, width: r * 2, height: r * 2))
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
    drawRing(in: ctx, size: CGFloat(pixels), menuBar: menuBar)

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

private func drawIOSAppIcon(in ctx: CGContext, size s: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: s, height: s)

    // Sunset violet → coral (distinct from previous blue orbit icon).
    fillGradient(
        in: ctx,
        rect: full,
        colors: [
            cgColor(0.28, 0.11, 0.48),
            cgColor(0.45, 0.18, 0.62),
            cgColor(0.88, 0.36, 0.22),
            cgColor(0.98, 0.55, 0.18),
        ],
        locations: [0, 0.38, 0.72, 1]
    )

    let c = CGPoint(x: s * 0.5, y: s * 0.48)
    let mark = cgColor(1.0, 0.97, 0.94)
    let glow = cgColor(1.0, 0.82, 0.55)

    // Soft halo behind mark (opaque blend)
    fillRing(in: ctx, center: c, outer: s * 0.30, inner: s * 0.255, color: cgColor(0.95, 0.72, 0.58))

    // Bold rounded X — filled bars, no stroke halos
    let barLen = s * 0.38
    let barW = s * 0.105
    let corner = barW * 0.5
    for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.setFillColor(mark)
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: -barLen / 2, y: -barW / 2, width: barLen, height: barW),
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        ))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Proxy arc accents (top-right / bottom-left)
    func drawArc(center: CGPoint, radius: CGFloat, thickness: CGFloat, start: CGFloat, end: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: radius - thickness, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }
    drawArc(
        center: CGPoint(x: c.x + s * 0.02, y: c.y - s * 0.02),
        radius: s * 0.36,
        thickness: s * 0.038,
        start: -.pi * 0.18,
        end: .pi * 0.42,
        color: glow
    )
    drawArc(
        center: c,
        radius: s * 0.22,
        thickness: s * 0.028,
        start: .pi * 0.62,
        end: .pi * 1.22,
        color: cgColor(1.0, 0.92, 0.78)
    )

    // Routing nodes (DNS / split hint)
    let nodes: [(CGPoint, CGColor)] = [
        (CGPoint(x: s * 0.22, y: s * 0.78), cgColor(0.55, 0.85, 0.95)),
        (CGPoint(x: s * 0.50, y: s * 0.84), mark),
        (CGPoint(x: s * 0.78, y: s * 0.76), glow),
    ]
    for (pt, color) in nodes {
        let r = s * 0.028
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
    ctx.setFillColor(cgColor(0.98, 0.55, 0.18))
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
savePNG(pixels: 72, menuBar: true, to: assets.appendingPathComponent("MenuBarIcon.imageset/icon.png"))
savePNG(pixels: 256, menuBar: false, to: assets.appendingPathComponent("AppIcon.appiconset/icon_256x256.png"))
savePNG(pixels: 512, menuBar: false, to: assets.appendingPathComponent("AppIcon.appiconset/icon_512x512.png"))
savePNG(pixels: 1024, menuBar: false, to: assets.appendingPathComponent("AppIcon.appiconset/icon_1024x1024.png"))

let iosAssets = root.appendingPathComponent("BashXiOS/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iosAssets, withIntermediateDirectories: true)
saveIOSPNG(pixels: 1024, to: iosAssets.appendingPathComponent("AppIcon-1024.png"))
print("Icons written to \(assets.path) and \(iosAssets.path)")
