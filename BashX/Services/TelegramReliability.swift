import Foundation
#if os(macOS)
import AppKit
#endif

/// Keep Telegram usable while BashX is running (system proxy + routing + node health).
enum TelegramReliability {
    /// Prefer API host — t.me redirects/CDN often false-fail url-test / health probes.
    static let probeURL = "https://api.telegram.org"
    static let fallbackProbeURL = "https://t.me"
    static let autoTestURL = "https://api.telegram.org"

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

    /// DC / media ranges clients dial as bare IPs (keepcoder / Telegra2 bypass system proxy).
    static let dcIPv4CIDRs: [String] = [
        "149.154.160.0/20",
        "91.108.0.0/16",
        "91.105.192.0/23",
        "185.76.151.0/24",
        "95.161.64.0/20",
    ]

    static let dcIPv6CIDRs: [String] = [
        "2001:67c:4e8::/48",
        "2001:b28:f23c::/48",
        "2001:b28:f23d::/48",
        "2001:b28:f23f::/48",
    ]

    /// Running Telegram-family apps (Desktop / keepcoder / Telegra2 / …).
    struct RunningClients: Equatable {
        /// Telegram Desktop (`com.tdesktop.Telegram`) — honors system SOCKS/HTTP proxy.
        var desktop: Bool
        /// Mac native / renamed (keepcoder, Telegra2, …) — dials DC bare IPs; needs TUN.
        var nativeMac: Bool

        var any: Bool { desktop || nativeMac }
        /// Bare-IP MTProto clients must enter TUN; system proxy alone is not enough.
        var needsTunCapture: Bool { nativeMac }
    }

    static func runningClients() -> RunningClients {
        #if os(macOS)
        var desktop = false
        var nativeMac = false
        for app in NSWorkspace.shared.runningApplications {
            let bid = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let path = app.bundleURL?.path.lowercased() ?? ""
            let isTG = bid.contains("telegram") || bid.contains("keepcoder")
                || name.contains("telegram") || name.contains("telegra")
                || path.contains("telegram.app") || path.contains("telegra2.app")
            guard isTG else { continue }
            if bid.contains("tdesktop") || bid == "org.telegram.desktop" {
                desktop = true
            } else {
                // keepcoder / Telegra2.app / other masquerades
                nativeMac = true
            }
        }
        return RunningClients(desktop: desktop, nativeMac: nativeMac)
        #else
        return RunningClients(desktop: false, nativeMac: false)
        #endif
    }

    static func isTelegramRunning() -> Bool {
        runningClients().any
    }
}
