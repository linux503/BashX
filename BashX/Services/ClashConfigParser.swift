import Foundation
import Yams

enum ConfigError: LocalizedError {
    case empty
    case invalidYAML
    case noProxies

    var errorDescription: String? {
        switch self {
        case .empty: return "订阅内容为空"
        case .invalidYAML: return "无法解析订阅内容"
        case .noProxies: return "未找到可用节点"
        }
    }
}

enum ClashConfigParser {
    static func parse(_ data: Data) throws -> (nodes: [ProxyNode], rawRoot: [String: Any]) {
        guard !data.isEmpty else { throw ConfigError.empty }
        let text = try normalizeToText(data)

        if looksLikeURIList(text) {
            let proxies = ShareLinkParser.parseLines(text)
            guard !proxies.isEmpty else { throw ConfigError.noProxies }
            return (nodesFromProxies(proxies), ["proxies": proxies])
        }

        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw ConfigError.invalidYAML
        }

        let proxyList = collectProxies(from: root)

        guard !proxyList.isEmpty else { throw ConfigError.noProxies }
        return (nodesFromProxies(proxyList), root)
    }

    static func buildConfig(
        nodes: [ProxyNode],
        selectedName: String?,
        mixedPort: Int,
        controller: String,
        secret: String,
        rules: [String],
        tunEnabled: Bool,
        tunStack: String,
        mode: ProxyMode = .rule,
        allowLan: Bool = false,
        turboMode: Bool = true,
        domainSniffing: Bool = true,
        dnsPreference: DnsPreference = .smart
    ) -> String {
        let proxies: [[String: Any]] = nodes.map { node in
            var dict: [String: Any] = [:]
            for (k, v) in node.raw {
                dict[k] = unwrap(v.value)
            }
            dict["name"] = node.name
            dict["type"] = node.type
            if !node.server.isEmpty { dict["server"] = node.server }
            if node.port > 0 { dict["port"] = node.port }
            return dict
        }

        let names = nodes.map(\.name)
        let selected = selectedName.flatMap { names.contains($0) ? $0 : nil }
        // Keep MATCH,PROXY but default PROXY selection to AUTO for usable out-of-box routing.
        let rewrittenRules = (rules.isEmpty ? AppSettings.defaultRules : rules).map { rule -> String in
            if rule.trimmingCharacters(in: .whitespaces).uppercased() == "MATCH,PROXY" {
                return "MATCH,PROXY"
            }
            return rule
        }
        let finalRules = rewrittenRules.isEmpty ? AppSettings.defaultRules : rewrittenRules

        let proxyGroupList: [String] = {
            // Prefer selected → AUTO → nodes → DIRECT. Never put DIRECT first when nodes exist,
            // otherwise foreign sites (Google etc.) silently go direct and fail.
            var list: [String]
            if names.isEmpty {
                list = ["DIRECT"]
            } else {
                list = ["AUTO"] + names + ["DIRECT"]
            }
            if let selected {
                list.removeAll { $0 == selected }
                list.insert(selected, at: 0)
            }
            return list
        }()

        var root: [String: Any] = [
            "mixed-port": mixedPort,
            "allow-lan": allowLan,
            "bind-address": allowLan ? "*" : "127.0.0.1",
            "mode": mode.rawValue,
            "log-level": "warning",
            "external-controller": controller,
            "secret": secret,
            "ipv6": false,
            // false: GEOIP uses geoip.metadb (already cached). true would require GeoIP.dat from GitHub.
            "geodata-mode": false,
            "geo-auto-update": false,
            "geo-update-interval": 168,
            // jsDelivr mirrors — GitHub releases often time out from mainland networks
            "geox-url": [
                "geoip": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb",
                "geosite": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
                "mmdb": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
            ],
            "dns": DnsPreference.dnsBlock(for: dnsPreference),
            "proxies": proxies,
            "proxy-groups": [
                [
                    "name": "PROXY",
                    "type": "select",
                    "proxies": proxyGroupList
                ],
                [
                    "name": "AUTO",
                    "type": "url-test",
                    "proxies": names.isEmpty ? ["DIRECT"] : names,
                    "url": "http://www.gstatic.com/generate_204",
                    "interval": turboMode ? 600 : 300,
                    "tolerance": turboMode ? 80 : 50,
                    "lazy": turboMode
                ]
            ],
            "rules": finalRules
        ]

        if turboMode {
            root["tcp-concurrent"] = true
            root["unified-delay"] = true
            root["find-process-mode"] = "off"
            root["keep-alive-interval"] = 30
            if domainSniffing {
                root["sniffer"] = [
                    "enable": true,
                    "force-dns-mapping": true,
                    "parse-pure-ip": true,
                    "override-destination": true,
                    "sniff": [
                        "HTTP": ["ports": [80, 8080, 8880]],
                        "TLS": ["ports": [443, 8443]],
                        "QUIC": ["ports": [443, 8443]]
                    ],
                    "skip-domain": [
                        "Mijia Cloud",
                        "+.push.apple.com"
                    ]
                ]
            }
        }

        if tunEnabled {
            root["tun"] = [
                "enable": true,
                "stack": tunStack.isEmpty ? "mixed" : tunStack,
                "auto-route": true,
                "auto-detect-interface": true,
                "dns-hijack": ["any:53"],
                "strict-route": false
            ]
        }

        return (try? Yams.dump(object: root)) ?? ""
    }

    // MARK: - Private

    private static let nonProxyTypes: Set<String> = [
        "direct", "reject", "select", "url-test", "fallback", "load-balance", "relay", "pass", "dns", "block"
    ]

    /// Collect proxy dicts from proxies / Proxy / proxy-providers / inline proxy-groups.
    private static func collectProxies(from root: [String: Any]) -> [[String: Any]] {
        var list: [[String: Any]] = []
        if let proxies = root["proxies"] as? [[String: Any]] { list.append(contentsOf: proxies) }
        if let proxies = root["Proxy"] as? [[String: Any]] { list.append(contentsOf: proxies) }
        if let proxies = root["proxy"] as? [[String: Any]] { list.append(contentsOf: proxies) }

        if let providers = root["proxy-providers"] as? [String: Any] {
            for (_, value) in providers {
                guard let dict = value as? [String: Any] else { continue }
                if let inline = dict["proxies"] as? [[String: Any]] {
                    list.append(contentsOf: inline)
                }
            }
        }

        if let groups = root["proxy-groups"] as? [[String: Any]] {
            for group in groups {
                guard let items = group["proxies"] as? [Any] else { continue }
                for item in items {
                    guard let dict = item as? [String: Any],
                          dict["type"] != nil,
                          dict["name"] != nil else { continue }
                    list.append(dict)
                }
            }
        }

        return list.filter(isProxyDict)
    }

    private static func isProxyDict(_ item: [String: Any]) -> Bool {
        guard let type = (item["type"] as? String)?.lowercased(), !type.isEmpty else { return false }
        if nonProxyTypes.contains(type) { return false }
        guard let name = item["name"] as? String, !name.isEmpty else { return false }
        if name.uppercased() == "DIRECT" || name.uppercased() == "REJECT" { return false }
        return true
    }

    private static func normalizeToText(_ data: Data) throws -> String {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw ConfigError.empty
        }

        if raw.contains("proxies:") || raw.contains("Proxy:")
            || raw.contains("proxy-providers:") || looksLikeURIList(raw) {
            return raw
        }

        if let decoded = decodeFlexibleBase64(raw),
           let text = String(data: decoded, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return raw
    }

    private static func looksLikeURIList(_ text: String) -> Bool {
        let sample = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(5)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !sample.isEmpty else { return false }
        let prefixes = ["ss://", "ssr://", "vmess://", "vless://", "trojan://", "hysteria2://", "hy2://", "tuic://"]
        return sample.contains { line in prefixes.contains(where: { line.lowercased().hasPrefix($0) }) }
    }

    private static func decodeFlexibleBase64(_ raw: String) -> Data? {
        let cleaned = raw
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        return Data(base64Encoded: padded)
    }

    private static func nodesFromProxies(_ proxyList: [[String: Any]]) -> [ProxyNode] {
        var nodes: [ProxyNode] = []
        nodes.reserveCapacity(proxyList.count)
        var usedNames = Set<String>()

        for item in proxyList {
            guard var name = item["name"] as? String,
                  let type = item["type"] as? String else { continue }

            if usedNames.contains(name) {
                var i = 2
                while usedNames.contains("\(name) (\(i))") { i += 1 }
                name = "\(name) (\(i))"
            }
            usedNames.insert(name)

            let server = (item["server"] as? String) ?? ""
            let port = intValue(item["port"]) ?? 0
            var rawItem = item
            rawItem["name"] = name
            let raw = rawItem.mapValues { AnyCodable($0) }
            nodes.append(ProxyNode(name: name, type: type, server: server, port: port, raw: raw))
        }
        return nodes
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let p = value as? Int { return p }
        if let p = value as? Int64 { return Int(p) }
        if let p = value as? String { return Int(p) }
        return nil
    }

    private static func unwrap(_ value: Any) -> Any {
        if let nested = value as? AnyCodable {
            return unwrap(nested.value)
        }
        if let array = value as? [Any] {
            return array.map(unwrap)
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues(unwrap)
        }
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { unwrap($0.value) }
        }
        return value
    }
}

enum ShareLinkParser {
    static func parseLines(_ text: String) -> [[String: Any]] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseURI(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func parseURI(_ line: String) -> [String: Any]? {
        let lower = line.lowercased()
        if lower.hasPrefix("ss://") { return parseShadowsocks(line) }
        if lower.hasPrefix("trojan://") { return parseTrojan(line) }
        return nil
    }

    // SIP002: ss://base64(method:password)@host:port/?plugin=...#name
    // Legacy: ss://base64(method:password@host:port)#name
    private static func parseShadowsocks(_ line: String) -> [String: Any]? {
        let withoutScheme = String(line.dropFirst(5))
        let hashParts = withoutScheme.split(separator: "#", maxSplits: 1).map(String.init)
        let main = hashParts[0]
        let name = hashParts.count > 1
            ? (hashParts[1].removingPercentEncoding ?? hashParts[1])
            : "SS"

        if let at = main.firstIndex(of: "@") {
            let user = String(main[..<at])
            var hostPart = String(main[main.index(after: at)...])
            var query: String?
            if let q = hostPart.firstIndex(of: "?") {
                query = String(hostPart[hostPart.index(after: q)...])
                hostPart = String(hostPart[..<q])
            }
            hostPart = hostPart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // host:port or [ipv6]:port
            guard let colon = hostPart.lastIndex(of: ":"),
                  let port = Int(hostPart[hostPart.index(after: colon)...]) else { return nil }
            let host = String(hostPart[..<colon])
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard let methodPass = decodeUserInfo(user) else { return nil }
            let parts = methodPass.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            var dict: [String: Any] = [
                "name": name,
                "type": "ss",
                "server": host,
                "port": port,
                "cipher": parts[0],
                "password": parts[1]
            ]
            if let query {
                applySSPlugin(fromQuery: query, into: &dict)
            }
            return dict
        }

        // Legacy whole-body base64 after ss://
        guard let decoded = decodeFlexibleBase64(main),
              let decodedText = String(data: decoded, encoding: .utf8) else { return nil }
        guard let at = decodedText.lastIndex(of: "@") else { return nil }
        let userInfo = String(decodedText[..<at])
        let hostPort = String(decodedText[decodedText.index(after: at)...])
        let mp = userInfo.split(separator: ":", maxSplits: 1).map(String.init)
        let hp = hostPort.split(separator: ":", maxSplits: 1).map(String.init)
        guard mp.count == 2, hp.count == 2, let port = Int(hp[1]) else { return nil }
        return [
            "name": name,
            "type": "ss",
            "server": hp[0],
            "port": port,
            "cipher": mp[0],
            "password": mp[1]
        ]
    }

    private static func applySSPlugin(fromQuery query: String, into dict: inout [String: Any]) {
        let items = query.split(separator: "&").compactMap { pair -> (String, String)? in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            return (kv[0], kv[1].removingPercentEncoding ?? kv[1])
        }
        guard let pluginValue = items.first(where: { $0.0 == "plugin" })?.1 else { return }

        // simple-obfs;obfs=http;obfs-host=xxx
        let parts = pluginValue.split(separator: ";").map(String.init)
        guard let pluginName = parts.first?.lowercased() else { return }

        var opts: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { opts[kv[0]] = kv[1] }
        }

        if pluginName.contains("obfs") {
            dict["plugin"] = "obfs"
            var pluginOpts: [String: Any] = [:]
            if let mode = opts["obfs"] { pluginOpts["mode"] = mode }
            if let host = opts["obfs-host"] { pluginOpts["host"] = host }
            dict["plugin-opts"] = pluginOpts
        } else if pluginName.contains("v2ray") {
            dict["plugin"] = "v2ray-plugin"
            var pluginOpts: [String: Any] = [:]
            if let mode = opts["mode"] { pluginOpts["mode"] = mode }
            if let host = opts["host"] { pluginOpts["host"] = host }
            if opts["tls"] == "true" || opts.keys.contains("tls") { pluginOpts["tls"] = true }
            dict["plugin-opts"] = pluginOpts
        }
    }

    private static func parseTrojan(_ line: String) -> [String: Any]? {
        guard let url = URLComponents(string: line),
              let host = url.host,
              let port = url.port,
              let password = url.user?.removingPercentEncoding else { return nil }
        let name = url.fragment.flatMap { $0.removingPercentEncoding } ?? "Trojan"
        var dict: [String: Any] = [
            "name": name,
            "type": "trojan",
            "server": host,
            "port": port,
            "password": password
        ]
        if let sni = url.queryItems?.first(where: { $0.name == "sni" || $0.name == "peer" })?.value {
            dict["sni"] = sni
        }
        return dict
    }

    private static func decodeUserInfo(_ user: String) -> String? {
        if user.contains(":") { return user.removingPercentEncoding }
        guard let data = decodeFlexibleBase64(user),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func decodeFlexibleBase64(_ raw: String) -> Data? {
        let cleaned = raw
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}
