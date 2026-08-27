import Foundation

/// Google / Translate routing helpers (mirrors TelegramReliability pattern).
enum GoogleReliability {
    static let probeURL = "https://www.google.com/generate_204"

    /// Prefer low-latency hubs for GOOGLE url-test (same pool as Telegram).
    static func preferredNodes(from names: [String]) -> [String] {
        ClashConfigParser.preferredRegionNodes(from: names)
    }
}
