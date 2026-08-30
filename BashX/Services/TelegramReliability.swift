import Foundation
#if os(macOS)
import AppKit
#endif

/// Keep Telegram usable while BashX is running (system proxy + routing + node health).
enum TelegramReliability {
    static let probeURL = "https://t.me"
    static let fallbackProbeURL = "https://api.telegram.org"
    static let autoTestURL = "https://t.me"

    static let domainRules: [String] = [
        "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
        "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
        "DOMAIN-SUFFIX,t.me,TELEGRAM",
        "DOMAIN-SUFFIX,graph.org,TELEGRAM",
        "DOMAIN-SUFFIX,tdesktop.com,TELEGRAM",
        "DOMAIN-KEYWORD,telegram,TELEGRAM",
    ]

    static let dnsFakeIPFilters: [String] = [
        "+.telegram.org",
        "+.telegram-cdn.org",
        "+.cdn-telegram.org",
        "+.telesco.pe",
        "+.t.me",
        "+.graph.org",
        "+.tdesktop.com",
        "+.telegra.ph",
    ]

    static func isTelegramRunning() -> Bool {
        #if os(macOS)
        NSWorkspace.shared.runningApplications.contains { app in
            let bid = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return bid.contains("telegram") || name == "telegram"
        }
        #else
        false
        #endif
    }
}
