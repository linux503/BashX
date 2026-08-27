import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum IOSAltIconGenMain {
    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : FileManager.default.currentDirectoryPath)
        IOSAltIconGen.run(root: root)
    }
}

/// Generates iOS alternate app icons + picker previews (opaque full-bleed).
enum IOSAltIconGen {
    static func run(root: URL) {
        let assets = root.appendingPathComponent("BashXiOS/Assets.xcassets")
        let primarySet = assets.appendingPathComponent("AppIcon.appiconset")
        try? FileManager.default.createDirectory(at: primarySet, withIntermediateDirectories: true)

        let primary = LogoStyle.iosPrimary
        for style in LogoStyle.allCases {
            if style == primary {
                saveOpaquePNG(LogoRenderer.iosAppIcon(style: style, pixels: 1024),
                              to: primarySet.appendingPathComponent("AppIcon-1024.png"))
            } else {
                let setDir = assets.appendingPathComponent("AppIcon-\(style.rawValue).appiconset")
                try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
                let png = setDir.appendingPathComponent("AppIcon-\(style.rawValue)-1024.png")
                saveOpaquePNG(LogoRenderer.iosAppIcon(style: style, pixels: 1024), to: png)
                writeAppIconJSON(setDir, filename: "AppIcon-\(style.rawValue)-1024.png")
            }

            let previewDir = assets.appendingPathComponent("LogoPreview-\(style.rawValue).imageset")
            try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
            let previewPNG = previewDir.appendingPathComponent("LogoPreview-\(style.rawValue).png")
            saveOpaquePNG(LogoRenderer.iosAppIcon(style: style, pixels: 180), to: previewPNG)
            writePreviewJSON(previewDir, filename: "LogoPreview-\(style.rawValue).png")
        }

        // Sanity: refuse to ship all-black icons.
        let check = primarySet.appendingPathComponent("AppIcon-1024.png")
        if isMostlyBlack(check) {
            fputs("ERROR: AppIcon-1024.png is black — render failed\n", stderr)
            exit(1)
        }
        print("iOS opaque icons → \(assets.path)")

        // Mac dock / Finder / menu bar — same brand mark as iOS primary.
        writeMacIcons(root: root, style: LogoStyle.default)
    }

    private static func writeMacIcons(root: URL, style: LogoStyle) {
        let macAssets = root.appendingPathComponent("BashX/Assets.xcassets")
        let appIconDir = macAssets.appendingPathComponent("AppIcon.appiconset")
        let menuDir = macAssets.appendingPathComponent("MenuBarIcon.imageset")
        try? FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: menuDir, withIntermediateDirectories: true)

        let appSizes: [(String, Int)] = [
            ("app_16.png", 16), ("app_16@2x.png", 32),
            ("app_32.png", 32), ("app_32@2x.png", 64),
            ("app_128.png", 128), ("app_128@2x.png", 256),
            ("app_256.png", 256), ("app_256@2x.png", 512),
            ("app_512.png", 512), ("app_512@2x.png", 1024),
        ]
        for (name, px) in appSizes {
            saveAlphaPNG(LogoRenderer.appIcon(style: style, pixels: px),
                         to: appIconDir.appendingPathComponent(name))
        }
        saveAlphaPNG(LogoRenderer.templateImage(style: style, size: 16),
                     to: menuDir.appendingPathComponent("icon_16.png"))
        saveAlphaPNG(LogoRenderer.templateImage(style: style, size: 32),
                     to: menuDir.appendingPathComponent("icon_16@2x.png"))
        saveAlphaPNG(LogoRenderer.templateImage(style: style, size: 36),
                     to: menuDir.appendingPathComponent("icon.png"))
        print("Mac AppIcon + MenuBarIcon → \(macAssets.path) (\(style.rawValue))")
    }

    /// Preserve alpha (Mac dock icons need transparent margin).
    private static func saveAlphaPNG(_ image: NSImage, to url: URL) {
        guard let src = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("ERROR: no cgImage for \(url.lastPathComponent)\n", stderr)
            return
        }
        let pxW = src.width
        let pxH = src.height
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Flatten to opaque RGB via CGContext (NSBitmapImageRep path was writing empty black PNGs).
    private static func saveOpaquePNG(_ image: NSImage, to url: URL) {
        let w = max(1, Int(image.size.width.rounded()))
        let h = max(1, Int(image.size.height.rounded()))
        // Prefer true pixel dimensions when available.
        let pxW: Int
        let pxH: Int
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pxW = cg.width
            pxH = cg.height
        } else {
            pxW = w
            pxH = h
        }

        guard let src = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("ERROR: no cgImage for \(url.lastPathComponent)\n", stderr)
            return
        }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }

        let rect = CGRect(x: 0, y: 0, width: pxW, height: pxH)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.18, blue: 0.28, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(src, in: rect)

        guard let out = ctx.makeImage() else { return }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func isMostlyBlack(_ url: URL) -> Bool {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data else { return true }
        let ptr = CFDataGetBytePtr(data)!
        let len = CFDataGetLength(data)
        let bpp = max(3, cg.bitsPerPixel / 8)
        var bright = 0
        var samples = 0
        var i = 0
        while i + 2 < len {
            let r = Int(ptr[i]), g = Int(ptr[i + 1]), b = Int(ptr[i + 2])
            if r + g + b > 40 { bright += 1 }
            samples += 1
            i += bpp * 64 // sparse sample
        }
        return samples > 0 && Double(bright) / Double(samples) < 0.01
    }

    private static func writeAppIconJSON(_ dir: URL, filename: String) {
        let json = """
        {
          "images" : [
            {
              "filename" : "\(filename)",
              "idiom" : "universal",
              "platform" : "ios",
              "size" : "1024x1024"
            }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
        try? json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }

    private static func writePreviewJSON(_ dir: URL, filename: String) {
        let json = """
        {
          "images" : [
            { "filename" : "\(filename)", "idiom" : "universal", "scale" : "1x" },
            { "idiom" : "universal", "scale" : "2x" },
            { "idiom" : "universal", "scale" : "3x" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
        try? json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }
}
