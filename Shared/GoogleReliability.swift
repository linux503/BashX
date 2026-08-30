import Foundation

/// Google / Translate routing helpers (mirrors TelegramReliability pattern).
enum GoogleReliability {
    /// GOOGLE url-test + auto-pick: must exercise the same path as translate.google.com web UI.
    static let probeURL =
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q=BashX"

    /// Fallback when translate API is rate-limited but Google edge is up.
    static let fallbackProbeURL = "https://www.google.com/generate_204"

    /// Prefer low-latency hubs for GOOGLE url-test (same pool as Telegram).
    static func preferredNodes(from names: [String]) -> [String] {
        ClashConfigParser.preferredRegionNodes(from: names)
    }
}
