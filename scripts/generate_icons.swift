#!/usr/bin/swift
// Generate BashX menu-bar (template) + macOS app icons + iOS app icon.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()

// MARK: - macOS menu bar + dock icons (bright yellow + dark X — BashX brand)

func drawAppMark(in ctx: CGContext, size s: CGFloat, menuBar: Bool) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if !menuBar {
        let inset = s * 0.04
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
        // Solid yellow base (guarantees Dock reads yellow even if gradient fails)
        ctx.setFillColor(CGColor(red: 1.0, green: 0.84, blue: 0.12, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        let colors = [
            CGColor(red: 0.98, green: 0.78, blue: 0.08, alpha: 1),
            CGColor(red: 1.0, green: 0.86, blue: 0.14, alpha: 1),
            CGColor(red: 1.0, green: 0.92, blue: 0.28, alpha: 1),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
            ctx.restoreGState()
        }
        // Soft gold rim
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.96, blue: 0.55, alpha: 0.55))
        ctx.setLineWidth(max(1, s * 0.014))
        ctx.addPath(path)
        ctx.strokePath()

        // Dark X on yellow for dock clarity
        ctx.setStrokeColor(CGColor(red: 0.12, green: 0.09, blue: 0.02, alpha: 1))
        ctx.setFillColor(CGColor(red: 0.12, green: 0.09, blue: 0.02, alpha: 1))
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
        ctx.setFillColor(CGColor(red: 0.12, green: 0.09, blue: 0.02, alpha: 1))
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
    let center = CGPoint(x: s * 0.5, y: s * 0.5)

    // Match Mac brand: bright yellow field + dark X (full-bleed, opaque for iOS).
    fillGradient(
        in: ctx,
        rect: full,
        colors: [
            cgColor(0.98, 0.78, 0.08),
            cgColor(1.0, 0.86, 0.14),
            cgColor(1.0, 0.92, 0.28),
        ],
        locations: [0, 0.5, 1]
    )
    // Soft highlight wash
    fillRadialGradient(
        in: ctx,
        rect: full,
        center: CGPoint(x: s * 0.32, y: s * 0.28),
        radius: s * 0.72,
        colors: [
            cgColor(1.0, 0.98, 0.72, 0.45),
            cgColor(1.0, 0.92, 0.28, 0.0),
        ],
        locations: [0, 1]
    )

    let ink = cgColor(0.12, 0.09, 0.02)
    ctx.setStrokeColor(ink)
    ctx.setFillColor(ink)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let length = s * 0.54
    let lw = max(2.4, s * 0.20)
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
    let hub = s * 0.055
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
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

    // Opaque yellow base (matches brand field).
    ctx.setFillColor(cgColor(1.0, 0.84, 0.12))
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

// Menu bar template — Ventura 16pt / 32px @2x
savePNG(pixels: 16, menuBar: true, to: menuDir.appendingPathComponent("icon_16.png"))
savePNG(pixels: 32, menuBar: true, to: menuDir.appendingPathComponent("icon_16@2x.png"))
savePNG(pixels: 36, menuBar: true, to: menuDir.appendingPathComponent("icon.png"))

let iosAssets = root.appendingPathComponent("BashXiOS/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: iosAssets, withIntermediateDirectories: true)
saveIOSPNG(pixels: 1024, to: iosAssets.appendingPathComponent("AppIcon-1024.png"))

// Keep markX alternate + in-app preview aligned with primary brand icon.
let iosCatalog = root.appendingPathComponent("BashXiOS/Assets.xcassets")
let markXIconDir = iosCatalog.appendingPathComponent("AppIcon-markX.appiconset")
let markXPreviewDir = iosCatalog.appendingPathComponent("LogoPreview-markX.imageset")
try! FileManager.default.createDirectory(at: markXIconDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: markXPreviewDir, withIntermediateDirectories: true)
saveIOSPNG(pixels: 1024, to: markXIconDir.appendingPathComponent("AppIcon-markX-1024.png"))
saveIOSPNG(pixels: 256, to: markXPreviewDir.appendingPathComponent("LogoPreview-markX.png"))

// Bundled About / panel artwork (keep in sync with AppIcon).
let logoResource = root.appendingPathComponent("BashX/Resources")
try! FileManager.default.createDirectory(at: logoResource, withIntermediateDirectories: true)
savePNG(pixels: 1024, menuBar: false, to: logoResource.appendingPathComponent("logo.png"))

print("Icons written to \(assets.path) and \(iosAssets.path)")
