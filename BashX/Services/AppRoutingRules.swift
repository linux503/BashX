import Foundation
#if os(macOS)
import AppKit
#endif

enum AppRoutingRules {
    static let routePresets: [(id: String, titleZh: String, titleEn: String)] = [
        ("PROXY", "主线路", "Main"),
        ("AUTO", "自动", "Auto"),
        ("DIRECT", "直连", "Direct"),
        ("OPENAI", "ChatGPT", "ChatGPT"),
        ("COPILOT", "Copilot", "Copilot"),
        ("GOOGLE", "Google", "Google"),
        ("TELEGRAM", "Telegram", "Telegram"),
        ("TWITTER", "Twitter", "Twitter"),
        ("NETFLIX", "Netflix", "Netflix"),
        ("CURSOR", "Cursor", "Cursor"),
        ("AI", "AI", "AI"),
        ("US", "美国", "US"),
        ("JP", "日本", "JP"),
        ("HK", "香港", "HK"),
    ]

    /// ClashX / Surge style common app presets — stable bundle id + process name.
    enum PresetCategory: String, CaseIterable, Identifiable {
        case im
        case browser
        case domestic
        case streaming
        case dev

        var id: String { rawValue }

        func title(lang: AppLanguage) -> String {
            switch self {
            case .im: return L10n.t("mac.apps.cat.im", lang)
            case .browser: return L10n.t("mac.apps.cat.browser", lang)
            case .domestic: return L10n.t("mac.apps.cat.domestic", lang)
            case .streaming: return L10n.t("mac.apps.cat.streaming", lang)
            case .dev: return L10n.t("mac.apps.cat.dev", lang)
            }
        }
    }

    struct CommonAppPreset: Identifiable, Hashable {
        var id: String { stableKey }
        var category: PresetCategory
        var labelZh: String
        var labelEn: String
        var processName: String
        var bundleId: String
        var proxyTarget: String

        var stableKey: String {
            let bid = bundleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !bid.isEmpty { return "bid:\(bid)" }
            return "proc:\(processName.lowercased())"
        }

        func label(lang: AppLanguage) -> String {
            lang.code == "en" ? labelEn : labelZh
        }

        func asRule(enabled: Bool = true, lang: AppLanguage = .current) -> AppRoutingRule {
            AppRoutingRule(
                enabled: enabled,
                label: label(lang: lang),
                processName: processName,
                bundleId: bundleId,
                proxyTarget: proxyTarget
            )
        }
    }

    /// Default per-app routes (参考 ClashX / Surge / Clash Verge 常见分组).
    static let commonPresets: [CommonAppPreset] = [
        // IM — Telegram 独立线路；国内 IM 直连
        .init(category: .im, labelZh: "Telegram", labelEn: "Telegram",
              processName: "Telegram", bundleId: "org.telegram.desktop", proxyTarget: "TELEGRAM"),
        .init(category: .im, labelZh: "微信", labelEn: "WeChat",
              processName: "WeChat", bundleId: "com.tencent.xinWeChat", proxyTarget: "DIRECT"),
        .init(category: .im, labelZh: "QQ", labelEn: "QQ",
              processName: "QQ", bundleId: "com.tencent.qq", proxyTarget: "DIRECT"),
        .init(category: .im, labelZh: "Discord", labelEn: "Discord",
              processName: "Discord", bundleId: "com.hnc.Discord", proxyTarget: "PROXY"),
        .init(category: .im, labelZh: "Slack", labelEn: "Slack",
              processName: "Slack", bundleId: "com.tinyspeck.slackmacgap", proxyTarget: "PROXY"),

        // Browser — Google 系走 GOOGLE 组；其余走代理
        .init(category: .browser, labelZh: "Google Chrome", labelEn: "Google Chrome",
              processName: "Google Chrome", bundleId: "com.google.Chrome", proxyTarget: "GOOGLE"),
        .init(category: .browser, labelZh: "Safari", labelEn: "Safari",
              processName: "Safari", bundleId: "com.apple.Safari", proxyTarget: "GOOGLE"),
        .init(category: .browser, labelZh: "Microsoft Edge", labelEn: "Microsoft Edge",
              processName: "Microsoft Edge", bundleId: "com.microsoft.edgemac", proxyTarget: "GOOGLE"),
        .init(category: .browser, labelZh: "Firefox", labelEn: "Firefox",
              processName: "firefox", bundleId: "org.mozilla.firefox", proxyTarget: "PROXY"),
        .init(category: .browser, labelZh: "Arc", labelEn: "Arc",
              processName: "Arc", bundleId: "company.thebrowser.Browser", proxyTarget: "PROXY"),

        // Domestic — 国内办公/娱乐直连
        .init(category: .domestic, labelZh: "钉钉", labelEn: "DingTalk",
              processName: "DingTalk", bundleId: "com.alibaba.DingTalkMac", proxyTarget: "DIRECT"),
        .init(category: .domestic, labelZh: "飞书", labelEn: "Lark",
              processName: "Lark", bundleId: "com.electron.lark", proxyTarget: "DIRECT"),
        .init(category: .domestic, labelZh: "哔哩哔哩", labelEn: "Bilibili",
              processName: "bilibili", bundleId: "com.bilibili.bilibili-mac", proxyTarget: "DIRECT"),
        .init(category: .domestic, labelZh: "网易云音乐", labelEn: "NetEase Music",
              processName: "NeteaseMusic", bundleId: "com.netease.163music", proxyTarget: "DIRECT"),
        .init(category: .domestic, labelZh: "腾讯会议", labelEn: "Tencent Meeting",
              processName: "TencentMeeting", bundleId: "com.tencent.meeting", proxyTarget: "DIRECT"),

        // Streaming / games — 海外服务走代理
        .init(category: .streaming, labelZh: "Spotify", labelEn: "Spotify",
              processName: "Spotify", bundleId: "com.spotify.client", proxyTarget: "PROXY"),
        .init(category: .streaming, labelZh: "Steam", labelEn: "Steam",
              processName: "steam_osx", bundleId: "com.valvesoftware.steam", proxyTarget: "PROXY"),
        .init(category: .streaming, labelZh: "Zoom", labelEn: "Zoom",
              processName: "zoom.us", bundleId: "us.zoom.xos", proxyTarget: "PROXY"),
        .init(category: .streaming, labelZh: "OBS", labelEn: "OBS",
              processName: "OBS", bundleId: "com.obsproject.obs-studio", proxyTarget: "PROXY"),

        // Dev — 终端直连；IDE 走代理拉包
        .init(category: .dev, labelZh: "终端", labelEn: "Terminal",
              processName: "Terminal", bundleId: "com.apple.Terminal", proxyTarget: "DIRECT"),
        .init(category: .dev, labelZh: "iTerm", labelEn: "iTerm",
              processName: "iTerm2", bundleId: "com.googlecode.iterm2", proxyTarget: "DIRECT"),
        .init(category: .dev, labelZh: "Cursor", labelEn: "Cursor",
              processName: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92", proxyTarget: "CURSOR"),
        .init(category: .dev, labelZh: "VS Code", labelEn: "VS Code",
              processName: "Code", bundleId: "com.microsoft.VSCode", proxyTarget: "PROXY"),
    ]

    /// Extra PROCESS-NAME lines so Electron helpers share the same policy as the main app.
    static func helperProcessRules(for processName: String, target: String) -> [String] {
        let base = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }
        let t = sanitizedTarget(target)
        if base.caseInsensitiveCompare("Cursor") == .orderedSame {
            return [
                "PROCESS-NAME,Cursor,\(t)",
                "PROCESS-NAME,Cursor Helper,\(t)",
                "PROCESS-NAME,Cursor Helper (GPU),\(t)",
                "PROCESS-NAME,Cursor Helper (Renderer),\(t)",
                "PROCESS-NAME,Cursor Helper (Plugin),\(t)",
                "PROCESS-NAME,Cursor Helper (Network),\(t)",
                "PROCESS-PATH,*Cursor.app/Contents/Frameworks/Cursor Helper*,\(t)",
                "PROCESS-PATH,*Cursor.app/Contents/MacOS/*,\(t)",
                "PROCESS-PATH,*Cursor Helper*.app/Contents/MacOS/*,\(t)",
            ]
        }
        return []
    }

    static func presets(in category: PresetCategory) -> [CommonAppPreset] {
        commonPresets.filter { $0.category == category }
    }

    static func existingIndex(of preset: CommonAppPreset, in rules: [AppRoutingRule]) -> Int? {
        rules.firstIndex { rule in
            ruleMatches(preset: preset, rule: rule)
        }
    }

    static func ruleMatches(preset: CommonAppPreset, rule: AppRoutingRule) -> Bool {
        let bid = preset.bundleId.lowercased()
        if !bid.isEmpty, rule.bundleId.lowercased() == bid { return true }
        return rule.processName.lowercased() == preset.processName.lowercased()
    }

    static func presetInstalled(_ preset: CommonAppPreset, in rules: [AppRoutingRule]) -> Bool {
        existingIndex(of: preset, in: rules) != nil
    }

    static func presetTitle(_ id: String, lang: AppLanguage) -> String {
        routePresets.first(where: { $0.id == id }).map {
            lang.code == "en" ? $0.titleEn : $0.titleZh
        } ?? id
    }

    /// Highest-priority rules — prepended before user prepend / smart rules.
    static func clashRules(from rules: [AppRoutingRule]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for rule in rules where rule.enabled {
            let process = rule.processName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !process.isEmpty else { continue }
            let target = sanitizedTarget(rule.proxyTarget)
            appendUnique(&out, &seen, "PROCESS-NAME,\(escape(process)),\(target)")
            let label = rule.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, !label.contains(",") {
                appendUnique(&out, &seen, "PROCESS-PATH,*\(escape(label)).app/Contents/MacOS/*,\(target)")
            }
            for helper in helperProcessRules(for: process, target: target) {
                appendUnique(&out, &seen, helper)
            }
        }
        return out
    }

    private static func sanitizedTarget(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "PROXY" : trimmed
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: "")
    }

    private static func appendUnique(_ out: inout [String], _ seen: inout Set<String>, _ line: String) {
        guard seen.insert(line).inserted else { return }
        out.append(line)
    }

    #if os(macOS)
    struct RunningApp: Identifiable, Hashable {
        var id: String { bundleId.isEmpty ? processName : bundleId }
        var label: String
        var processName: String
        var bundleId: String
        var icon: NSImage?

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
            lhs.id == rhs.id
        }
    }

    static func runningApps() -> [RunningApp] {
        var byID: [String: RunningApp] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let bundleId = app.bundleIdentifier ?? ""
            let processName = app.executableURL?.lastPathComponent ?? name
            let item = RunningApp(
                label: name,
                processName: processName,
                bundleId: bundleId,
                icon: app.icon
            )
            let key = bundleId.isEmpty ? processName.lowercased() : bundleId
            if byID[key] == nil {
                byID[key] = item
            }
        }
        return byID.values.sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }
    #endif
}
