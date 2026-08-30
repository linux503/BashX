import CoreGraphics
import UIKit

/// Responsive layout buckets for iPhone SE / XR / Plus / Pro Max class screens.
struct GameLayoutMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat

    static let referenceHeight: CGFloat = 852

    static let `default` = GameLayoutMetrics(
        width: 393,
        height: 852,
        safeTop: 59,
        safeBottom: 34
    )

    static func resolve(size: CGSize, safeInsets: UIEdgeInsets) -> GameLayoutMetrics {
        GameLayoutMetrics(
            width: max(1, size.width),
            height: max(1, size.height),
            safeTop: safeInsets.top,
            safeBottom: max(safeInsets.bottom, 8)
        )
    }

    /// 736pt class (8 Plus) and smaller tall phones.
    var compact: Bool { height < 780 }

    /// 932–956pt class (Pro Max / 17 Pro Max).
    var tall: Bool { height >= 900 }

    /// 428pt+ (Plus / Pro Max width).
    var wide: Bool { width >= 414 }

    var scale: CGFloat {
        let raw = height / Self.referenceHeight
        if compact { return min(0.94, max(0.82, raw)) }
        if tall { return min(1.16, max(1.0, raw)) }
        return min(1.08, max(0.9, raw))
    }

    var bubbleScale: CGFloat { compact ? 0.9 : (tall ? 1.04 : 1.0) }

    var hudFontScale: CGFloat { compact ? 0.9 : min(1.06, scale) }

    var shipMargin: CGFloat { max(28, (wide ? 42 : 34) * scale) }

    var shipBottomPad: CGFloat {
        safeBottom + height * (compact ? 0.12 : tall ? 0.165 : 0.15)
    }

    func playTop(isPlaying: Bool) -> CGFloat {
        let base = safeTop + (compact ? 24 : tall ? 36 : 30) * scale
        return isPlaying ? base : base + (compact ? 44 : tall ? 58 : 52) * scale
    }

    func playBottom(isPlaying: Bool) -> CGFloat {
        let base = safeBottom + (compact ? 10 : 12)
        let extra = isPlaying
            ? (compact ? 42 : tall ? 58 : 50) * scale
            : (compact ? 84 : tall ? 116 : 100) * scale
        return base + extra
    }

    var homeBottomPadding: CGFloat {
        safeBottom + (compact ? 72 : tall ? 104 : 88) * scale
    }

    var stopButtonBottom: CGFloat {
        safeBottom + (compact ? 16 : tall ? 28 : 22) * scale
    }

    var hudHorizontalPadding: CGFloat { wide ? 18 : 16 }

    /// Minimal gap when HUD is pinned to the physical top edge.
    var hudTopInset: CGFloat { 0 }

    var startButtonSize: CGSize {
        CGSize(
            width: min(max(196, width * 0.54), wide ? 268 : 248),
            height: max(46, (compact ? 50 : tall ? 58 : 54) * scale)
        )
    }

    var sunOffsetY: CGFloat { (compact ? -205 : tall ? -268 : -235) * scale }
}
