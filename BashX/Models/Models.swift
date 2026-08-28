import Foundation
import SwiftUI

enum ProxyMode: String, Codable, CaseIterable, Identifiable {
    case rule
    case global
    case direct

    var id: String { rawValue }

    var title: String { title(lang: .current) }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .rule: return L10n.t("proxy.rule", lang)
        case .global: return L10n.t("proxy.global", lang)
        case .direct: return L10n.t("proxy.direct", lang)
        }
    }

    var subtitle: String { subtitle(lang: .current) }

    func subtitle(lang: AppLanguage) -> String {
        switch self {
        case .rule: return L10n.t("proxy.rule.sub", lang)
        case .global: return L10n.t("proxy.global.sub", lang)
        case .direct: return L10n.t("proxy.direct.sub", lang)
        }
    }

    var systemImage: String {
        switch self {
        case .rule: return "arrow.triangle.branch"
        case .global: return "globe"
        case .direct: return "arrow.left.arrow.right"
        }
    }
}

/// Panel node list layout.
enum NodeDisplayMode: String, Codable, CaseIterable, Identifiable {
    case card
    case list

    var id: String { rawValue }

    var title: String { title(lang: .current) }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .card: return L10n.t("nodes.card", lang)
        case .list: return L10n.t("nodes.list", lang)
        }
    }

    var icon: String {
        switch self {
        case .card: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

/// Panel theme: light or dark (not tied to system).
enum AppAppearance: String, CaseIterable, Codable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var title: String { title(lang: .current) }
    func title(lang: AppLanguage) -> String {
        self == .light ? L10n.t("appearance.light", lang) : L10n.t("appearance.dark", lang)
    }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

struct ProxyNode: Identifiable, Hashable, Codable {
    var id: String { name }
    var name: String
    var type: String
    var server: String
    var port: Int
    var raw: [String: AnyCodable]
    var delayMs: Int?
    var testedAt: Date?

    /// Stable key for persisting speed-test results across renames / subscription merges.
    var delayCacheKey: String {
        "\(server.lowercased()):\(port)|\(type.lowercased())"
    }

    var delayText: String { delayText(lang: .current) }

    func delayText(lang: AppLanguage) -> String {
        guard let delayMs else { return "—" }
        if delayMs < 0 { return L10n.t("probe.timeout", lang) }
        return "\(delayMs) ms"
    }

    /// Subtitle under node name. Many airports share one entry IP with different ports —
    /// always include port so rows don't look identical.
    var endpointSubtitle: String {
        let t = type.uppercased()
        guard !server.isEmpty else { return t }
        guard port > 0 else { return "\(t) · \(server)" }
        if server.contains(":") && !server.hasPrefix("[") {
            return "\(t) · [\(server)]:\(port)"
        }
        return "\(t) · \(server):\(port)"
    }
}

/// Mac per-app outbound routing (PROCESS-NAME / PROCESS-PATH rules).
struct AppRoutingRule: Identifiable, Codable, Hashable {
    var id: UUID
    var enabled: Bool
    /// Display name (usually app localized name).
    var label: String
    /// Process name for PROCESS-NAME rule (e.g. `Google Chrome`).
    var processName: String
    /// Optional bundle id (e.g. `com.google.Chrome`).
    var bundleId: String
    /// Proxy group or leaf node: PROXY, AUTO, DIRECT, GOOGLE, TELEGRAM, or a node name.
    var proxyTarget: String

    init(
        id: UUID = UUID(),
        enabled: Bool = true,
        label: String = "",
        processName: String = "",
        bundleId: String = "",
        proxyTarget: String = "PROXY"
    ) {
        self.id = id
        self.enabled = enabled
        self.label = label
        self.processName = processName
        self.bundleId = bundleId
        self.proxyTarget = proxyTarget
    }
}

struct Subscription: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: String
    var updatedAt: Date?
    /// Included when updating / building node list.
    var enabled: Bool
    /// From `subscription-userinfo` response header.
    var userInfo: SubscriptionUserInfo?

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        updatedAt: Date? = nil,
        enabled: Bool = true,
        userInfo: SubscriptionUserInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.updatedAt = updatedAt
        self.enabled = enabled
        self.userInfo = userInfo
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, updatedAt, enabled, userInfo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        userInfo = try c.decodeIfPresent(SubscriptionUserInfo.self, forKey: .userInfo)
    }

    var trafficSummary: String? {
        guard let info = userInfo else { return nil }
        return "剩 \(info.remainingText)/\(info.totalText) · \(info.expireRelativeText)"
    }
}

struct AppSettings: Codable {
    var subscriptions: [Subscription] = []
    var selectedNodeName: String?
    var testURL: String = "https://www.gstatic.com/generate_204"
    var testTimeoutMs: Int = 4000
    var concurrency: Int = 6
    var clashBinaryPath: String = ""
    var externalController: String = "127.0.0.1:19090"
    var secret: String = ""
    var mixedPort: Int = 17890
    /// When true, mixed-port listens on all interfaces so other devices can use BashX as proxy.
    var allowLan: Bool = false
    /// Auto-enable system proxy while BashX runs (Telegram / IM apps rely on it).
    var systemProxyEnabled: Bool = true
    /// User explicitly turned off system proxy in UI — skip auto-enable on launch.
    var userDisabledSystemProxy: Bool = false
    var tunEnabled: Bool = false
    /// iOS: true = TUN 捕获全 App 流量；false = 仅 HTTP 系统代理（微信/Telegram 无效，实验用）。
    var iosTunnelCapture: Bool = true
    var tunStack: String = "mixed"
    /// Block video / streaming ad domains via REJECT rules.
    var videoAdBlockEnabled: Bool = true
    /// Prefer launch at login (actual state comes from SMAppService).
    var launchAtLoginEnabled: Bool = false
    var menuNodeLimit: Int = 50
    /// Show ↓/↑ rates next to the menu-bar icon (off by default — wide glyphs hide in ❯❯ overflow).
    var showMenuBarTraffic: Bool = false
    /// Show BashX icon in the Dock (off = menu-bar only).
    var showDockIcon: Bool = false
    /// Allow plain `http://` subscription URLs (ATS + explicit opt-in).
    var allowInsecureHTTPSubscriptions: Bool = false
    /// Periodically re-test nodes and keep fastest ranked first.
    var autoSpeedTestEnabled: Bool = false
    /// Minutes between automatic speed tests (minimum 3).
    var autoSpeedTestIntervalMinutes: Int = 10
    /// After auto test, switch outbound to the fastest node.
    var autoSelectFastest: Bool = false
    /// mihomo throughput knobs: tcp-concurrent, lazy url-test, sniffing, etc.
    var turboMode: Bool = true
    /// Domain sniffing for better routing (used when turboMode is on).
    var domainSniffing: Bool = true
    /// DNS resolver preference for mihomo (smart / domestic / foreign).
    var dnsPreference: DnsPreference = .smart
    var rules: [String] = AppSettings.defaultRules
    /// Clash Verge-style prepend: custom rules always above base/smart rules; survive subscription & smart-rule upgrades.
    var rulesPrepend: [String] = []
    /// Tracks bundled ChinaSmartRules version for silent upgrades.
    var rulesVersion: Int = ChinaSmartRules.version
    /// Close active connections when switching nodes (Clash Verge default).
    var closeConnectionsOnSwitch: Bool = true
    /// Clash-like: rule / global / direct
    var proxyMode: ProxyMode = .rule
    /// Menu bar / panel logo style.
    var logoStyle: LogoStyle = .default
    /// Panel nodes tab: list or card grid.
    var nodeDisplayMode: NodeDisplayMode = .list
    /// Panel / settings color theme.
    var appearance: AppAppearance = .light
    /// Persisted node latency keyed by `ProxyNode.delayCacheKey`.
    var nodeDelayCache: [String: Int] = [:]
    /// iOS: show wallpaper camouflage on launch; unlock via tip card 5 taps.
    var iosDisguiseEnabled: Bool = true
    /// UI language: system / Chinese / English.
    var uiLanguage: AppLanguage = .system
    /// Mac: route specific apps through different proxy lines.
    var appRoutingRules: [AppRoutingRule] = []

    static let defaultRules: [String] = ChinaSmartRules.rules

    enum CodingKeys: String, CodingKey {
        case subscriptions, selectedNodeName, testURL, testTimeoutMs, concurrency
        case clashBinaryPath, externalController, secret, mixedPort, allowLan
        case systemProxyEnabled, userDisabledSystemProxy, tunEnabled, iosTunnelCapture, tunStack, videoAdBlockEnabled
        case launchAtLoginEnabled, menuNodeLimit, showMenuBarTraffic, showDockIcon, allowInsecureHTTPSubscriptions
        case autoSpeedTestEnabled, autoSpeedTestIntervalMinutes, autoSelectFastest, turboMode, domainSniffing, dnsPreference
        case rules, rulesPrepend, rulesVersion, closeConnectionsOnSwitch, proxyMode
        case logoStyle, nodeDisplayMode, appearance, nodeDelayCache, iosDisguiseEnabled, uiLanguage
        case appRoutingRules
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        selectedNodeName = try c.decodeIfPresent(String.self, forKey: .selectedNodeName)
        testURL = try c.decodeIfPresent(String.self, forKey: .testURL) ?? "https://www.gstatic.com/generate_204"
        testTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .testTimeoutMs) ?? 4000
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? 6
        clashBinaryPath = try c.decodeIfPresent(String.self, forKey: .clashBinaryPath) ?? ""
        externalController = try c.decodeIfPresent(String.self, forKey: .externalController) ?? "127.0.0.1:19090"
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        mixedPort = try c.decodeIfPresent(Int.self, forKey: .mixedPort) ?? 17890
        allowLan = try c.decodeIfPresent(Bool.self, forKey: .allowLan) ?? false
        systemProxyEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemProxyEnabled) ?? true
        userDisabledSystemProxy = try c.decodeIfPresent(Bool.self, forKey: .userDisabledSystemProxy) ?? false
        tunEnabled = try c.decodeIfPresent(Bool.self, forKey: .tunEnabled) ?? false
        iosTunnelCapture = try c.decodeIfPresent(Bool.self, forKey: .iosTunnelCapture) ?? true
        tunStack = try c.decodeIfPresent(String.self, forKey: .tunStack) ?? "mixed"
        videoAdBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoAdBlockEnabled) ?? true
        launchAtLoginEnabled = try c.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        menuNodeLimit = try c.decodeIfPresent(Int.self, forKey: .menuNodeLimit) ?? 50
        // Default off: icon+rates is wide and often vanishes into menu-bar overflow (❯❯) on notch Macs.
        showMenuBarTraffic = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarTraffic) ?? false
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        allowInsecureHTTPSubscriptions = try c.decodeIfPresent(Bool.self, forKey: .allowInsecureHTTPSubscriptions) ?? false
        autoSpeedTestEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSpeedTestEnabled) ?? false
        autoSpeedTestIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .autoSpeedTestIntervalMinutes) ?? 10
        autoSelectFastest = try c.decodeIfPresent(Bool.self, forKey: .autoSelectFastest) ?? false
        turboMode = try c.decodeIfPresent(Bool.self, forKey: .turboMode) ?? true
        domainSniffing = try c.decodeIfPresent(Bool.self, forKey: .domainSniffing) ?? true
        dnsPreference = try c.decodeIfPresent(DnsPreference.self, forKey: .dnsPreference) ?? .smart
        rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? AppSettings.defaultRules
        rulesPrepend = try c.decodeIfPresent([String].self, forKey: .rulesPrepend) ?? []
        rulesVersion = try c.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 0
        closeConnectionsOnSwitch = try c.decodeIfPresent(Bool.self, forKey: .closeConnectionsOnSwitch) ?? true
        proxyMode = try c.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? .rule
        logoStyle = try c.decodeIfPresent(LogoStyle.self, forKey: .logoStyle) ?? .default
        nodeDisplayMode = try c.decodeIfPresent(NodeDisplayMode.self, forKey: .nodeDisplayMode) ?? .card
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .light
        nodeDelayCache = try c.decodeIfPresent([String: Int].self, forKey: .nodeDelayCache) ?? [:]
        iosDisguiseEnabled = try c.decodeIfPresent(Bool.self, forKey: .iosDisguiseEnabled) ?? true
        uiLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .uiLanguage) ?? .system
        appRoutingRules = try c.decodeIfPresent([AppRoutingRule].self, forKey: .appRoutingRules) ?? []
        L10n.apply(uiLanguage)
    }
}

/// Type-erased Codable wrapper for preserving proxy YAML fields.
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type")
            throw EncodingError.invalidValue(value, context)
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
