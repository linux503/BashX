import Foundation
import SwiftUI

enum ProxyMode: String, Codable, CaseIterable, Identifiable {
    case rule
    case global
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rule: return "规则"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }

    var subtitle: String {
        switch self {
        case .rule: return "按规则分流"
        case .global: return "全部走代理"
        case .direct: return "全部直连"
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

    var title: String {
        switch self {
        case .card: return "卡片"
        case .list: return "列表"
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
    var title: String { self == .light ? "浅色" : "深色" }
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

    var delayText: String {
        guard let delayMs else { return "—" }
        if delayMs < 0 { return "超时" }
        return "\(delayMs) ms"
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
    var testURL: String = "http://www.gstatic.com/generate_204"
    var testTimeoutMs: Int = 2500
    var concurrency: Int = 8
    var clashBinaryPath: String = ""
    var externalController: String = "127.0.0.1:19090"
    var secret: String = ""
    var mixedPort: Int = 17890
    /// When true, mixed-port listens on all interfaces so other devices can use BashX as proxy.
    var allowLan: Bool = false
    var systemProxyEnabled: Bool = false
    var tunEnabled: Bool = false
    var tunStack: String = "mixed"
    /// Block video / streaming ad domains via REJECT rules.
    var videoAdBlockEnabled: Bool = true
    /// Prefer launch at login (actual state comes from SMAppService).
    var launchAtLoginEnabled: Bool = false
    var menuNodeLimit: Int = 50
    /// Show ↓/↑ rates next to the menu-bar icon.
    var showMenuBarTraffic: Bool = true
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
    /// Tracks bundled ChinaSmartRules version for silent upgrades.
    var rulesVersion: Int = ChinaSmartRules.version
    /// Clash-like: rule / global / direct
    var proxyMode: ProxyMode = .rule
    /// Menu bar / panel logo style.
    var logoStyle: LogoStyle = .ring
    /// Panel nodes tab: list or card grid.
    var nodeDisplayMode: NodeDisplayMode = .card
    /// Panel / settings color theme.
    var appearance: AppAppearance = .light
    /// Persisted node latency keyed by `ProxyNode.delayCacheKey`.
    var nodeDelayCache: [String: Int] = [:]

    static let defaultRules: [String] = ChinaSmartRules.rules

    enum CodingKeys: String, CodingKey {
        case subscriptions, selectedNodeName, testURL, testTimeoutMs, concurrency
        case clashBinaryPath, externalController, secret, mixedPort, allowLan
        case systemProxyEnabled, tunEnabled, tunStack, videoAdBlockEnabled
        case launchAtLoginEnabled, menuNodeLimit, showMenuBarTraffic, showDockIcon, allowInsecureHTTPSubscriptions
        case autoSpeedTestEnabled, autoSpeedTestIntervalMinutes, autoSelectFastest, turboMode, domainSniffing, dnsPreference
        case rules, rulesVersion, proxyMode
        case logoStyle, nodeDisplayMode, appearance, nodeDelayCache
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        selectedNodeName = try c.decodeIfPresent(String.self, forKey: .selectedNodeName)
        testURL = try c.decodeIfPresent(String.self, forKey: .testURL) ?? "http://www.gstatic.com/generate_204"
        testTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .testTimeoutMs) ?? 2500
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? 8
        clashBinaryPath = try c.decodeIfPresent(String.self, forKey: .clashBinaryPath) ?? ""
        externalController = try c.decodeIfPresent(String.self, forKey: .externalController) ?? "127.0.0.1:19090"
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        mixedPort = try c.decodeIfPresent(Int.self, forKey: .mixedPort) ?? 17890
        allowLan = try c.decodeIfPresent(Bool.self, forKey: .allowLan) ?? false
        systemProxyEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemProxyEnabled) ?? false
        tunEnabled = try c.decodeIfPresent(Bool.self, forKey: .tunEnabled) ?? false
        tunStack = try c.decodeIfPresent(String.self, forKey: .tunStack) ?? "mixed"
        videoAdBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoAdBlockEnabled) ?? true
        launchAtLoginEnabled = try c.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        menuNodeLimit = try c.decodeIfPresent(Int.self, forKey: .menuNodeLimit) ?? 50
        showMenuBarTraffic = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarTraffic) ?? true
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        allowInsecureHTTPSubscriptions = try c.decodeIfPresent(Bool.self, forKey: .allowInsecureHTTPSubscriptions) ?? false
        autoSpeedTestEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSpeedTestEnabled) ?? false
        autoSpeedTestIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .autoSpeedTestIntervalMinutes) ?? 10
        autoSelectFastest = try c.decodeIfPresent(Bool.self, forKey: .autoSelectFastest) ?? false
        turboMode = try c.decodeIfPresent(Bool.self, forKey: .turboMode) ?? true
        domainSniffing = try c.decodeIfPresent(Bool.self, forKey: .domainSniffing) ?? true
        dnsPreference = try c.decodeIfPresent(DnsPreference.self, forKey: .dnsPreference) ?? .smart
        rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? AppSettings.defaultRules
        rulesVersion = try c.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? 0
        proxyMode = try c.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? .rule
        logoStyle = try c.decodeIfPresent(LogoStyle.self, forKey: .logoStyle) ?? .ring
        nodeDisplayMode = try c.decodeIfPresent(NodeDisplayMode.self, forKey: .nodeDisplayMode) ?? .card
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .light
        nodeDelayCache = try c.decodeIfPresent([String: Int].self, forKey: .nodeDelayCache) ?? [:]
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
