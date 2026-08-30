import Foundation

enum ByteFormat {
    static func size(_ bytes: Int64) -> String {
        let v = Double(max(0, bytes))
        if v < 1024 { return String(format: "%.0f B", v) }
        if v < 1024 * 1024 { return String(format: "%.1f KB", v / 1024) }
        if v < 1024 * 1024 * 1024 { return String(format: "%.2f MB", v / (1024 * 1024)) }
        return String(format: "%.2f GB", v / (1024 * 1024 * 1024))
    }

    static func rate(_ bytesPerSec: Int64) -> String {
        fixedMegaRate(bytesPerSec)
    }

    static func fixedMegaLabel(_ bytesPerSec: Int64) -> String {
        let m = megaValue(bytesPerSec)
        if m >= 100 { return String(format: "%4.0fM", min(m, 9999)) }
        return String(format: "%4.1fM", min(m, 99.9))
    }

    static func fixedMegaRate(_ bytesPerSec: Int64) -> String {
        "\(fixedMegaNumber(bytesPerSec)) M/s"
    }

    static func fixedMegaNumber(_ bytesPerSec: Int64) -> String {
        let m = megaValue(bytesPerSec)
        if m >= 100 { return String(format: "%.0f", min(m, 9999)) }
        return String(format: "%.1f", min(m, 99.9))
    }

    private static func megaValue(_ bytesPerSec: Int64) -> Double {
        Double(max(0, bytesPerSec)) / (1024.0 * 1024.0)
    }

    static func compactRate(_ bytesPerSec: Int64) -> String {
        let v = Double(max(0, bytesPerSec))
        if v < 1024 { return String(format: "%.0fB", v) }
        if v < 1024 * 1024 { return String(format: "%.0fK", v / 1024) }
        if v < 1024 * 1024 * 1024 { return String(format: "%.1fM", v / (1024 * 1024)) }
        return String(format: "%.1fG", v / (1024 * 1024 * 1024))
    }

    static func menuBarCompact(_ bytesPerSec: Int64) -> String {
        let v = Double(max(0, bytesPerSec))
        if v < 1024 {
            return String(format: "%.0fB", min(v, 999))
        }
        if v < 1024 * 1024 {
            let k = v / 1024
            if k < 100 { return String(format: "%.1fK", k) }
            return String(format: "%.0fK", min(k, 999))
        }
        if v < 1024 * 1024 * 1024 {
            let m = v / (1024 * 1024)
            if m < 100 { return String(format: "%.1fM", m) }
            return String(format: "%.0fM", min(m, 999))
        }
        let g = v / (1024 * 1024 * 1024)
        if g < 10 { return String(format: "%.1fG", g) }
        return String(format: "%.0fG", min(g, 99))
    }

    static func menuBarFixed(_ bytesPerSec: Int64) -> String {
        let v = Double(max(0, bytesPerSec))
        if v < 1024 {
            return String(format: "%.0fB", min(v, 999))
        }
        if v < 1024 * 1024 {
            let k = min(v / 1024, 999)
            if k < 10 { return String(format: "%.1fK", k) }
            return String(format: "%.0fK", k)
        }
        if v < 1024 * 1024 * 1024 {
            let m = min(v / (1024 * 1024), 999)
            if m < 10 { return String(format: "%.1fM", m) }
            return String(format: "%.0fM", m)
        }
        let g = min(v / (1024 * 1024 * 1024), 99)
        return g < 10 ? String(format: "%.1fG", g) : String(format: "%.0fG", g)
    }

    static func menuBarRate(_ bytesPerSec: Int64) -> String {
        menuBarCompact(bytesPerSec)
    }

    /// Fixed-width rate for panel top bar (8 chars, monospaced).
    static func panelRate(_ bytesPerSec: Int64) -> String {
        let v = Double(max(0, bytesPerSec))
        let raw: String
        if v < 1024 {
            raw = String(format: "%3.0f B/s", min(v, 999))
        } else if v < 1024 * 1024 {
            raw = String(format: "%4.0f K/s", min(v / 1024, 9999))
        } else if v < 1024 * 1024 * 1024 {
            let m = v / (1024 * 1024)
            raw = m >= 10
                ? String(format: "%4.0f M/s", min(m, 999))
                : String(format: "%4.1f M/s", m)
        } else {
            let g = v / (1024 * 1024 * 1024)
            raw = g >= 10
                ? String(format: "%4.0f G/s", min(g, 99))
                : String(format: "%4.1f G/s", g)
        }
        if raw.count >= 8 { return String(raw.prefix(8)) }
        return raw + String(repeating: " ", count: 8 - raw.count)
    }
}
