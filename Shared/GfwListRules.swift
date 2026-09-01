import Foundation

/// Upstream GFWList (AutoProxy) → Clash DOMAIN rules, default PROXY.
/// Source: https://github.com/gfwlist/gfwlist
enum GfwListRules {
    static let sourceURL = URL(string: "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt")!

    private static let refreshInterval: TimeInterval = 24 * 3600
    private static let cacheFileName = "gfwlist-clash.json"

    private struct Cache: Codable {
        var fetchedAt: Date
        var proxyRules: [String]
        var directRules: [String]
    }

    private static var cacheURL: URL {
        Paths.supportDir.appendingPathComponent(cacheFileName)
    }

    /// `@@` exceptions — must sit above gfwlist PROXY lines.
    static func directRules() -> [String] {
        loadCache()?.directRules ?? []
    }

    /// `||` / prefix / bare host lines from gfwlist → PROXY.
    static func proxyRules() -> [String] {
        loadCache()?.proxyRules ?? []
    }

    static var isReady: Bool { loadCache() != nil }

    /// Short label for rules editor / status bar.
    static var statusLine: String? {
        guard let cache = loadCache() else { return nil }
        return "GFWList 代理 \(cache.proxyRules.count) · 例外 \(cache.directRules.count)"
    }

    /// Download + parse when missing or stale. First launch blocks until cached.
    static func ensurePresent(progress: ((String) -> Void)? = nil) async throws {
        if let cache = loadCache() {
            if Date().timeIntervalSince(cache.fetchedAt) < refreshInterval { return }
            Task.detached(priority: .utility) {
                try? await refresh(progress: progress)
            }
            return
        }
        try await refresh(progress: progress)
    }

    @discardableResult
    static func refresh(progress: ((String) -> Void)? = nil) async throws -> (proxy: Int, direct: Int) {
        progress?("正在更新 GFWList…")
        let (data, _) = try await URLSession.shared.data(from: sourceURL)
        guard let parsed = parseAutoProxyPayload(data) else {
            throw NSError(domain: "GfwListRules", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "GFWList 解析失败",
            ])
        }
        let cache = Cache(
            fetchedAt: Date(),
            proxyRules: parsed.proxy,
            directRules: parsed.direct
        )
        try saveCache(cache)
        progress?("GFWList 已更新（\(parsed.proxy.count) 条代理）")
        return (parsed.proxy.count, parsed.direct.count)
    }

    // MARK: - Parse

    private static func parseAutoProxyPayload(_ data: Data) -> (proxy: [String], direct: [String])? {
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let decoded: String
        if let blob = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
           let text = String(data: blob, encoding: .utf8) {
            decoded = text
        } else {
            decoded = trimmed
        }

        var proxySeen = Set<String>()
        var directSeen = Set<String>()
        var proxy: [String] = []
        var direct: [String] = []

        for raw in decoded.split(whereSeparator: \.isNewline) {
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!") else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") { continue }

            let exception = line.hasPrefix("@@")
            if exception { line = String(line.dropFirst(2)) }

            guard let rule = clashRule(from: line, policy: exception ? "DIRECT" : "PROXY") else { continue }
            if exception {
                guard !directSeen.contains(rule) else { continue }
                directSeen.insert(rule)
                direct.append(rule)
            } else {
                guard !proxySeen.contains(rule) else { continue }
                proxySeen.insert(rule)
                proxy.append(rule)
            }
        }
        return (proxy, direct)
    }

    private static func clashRule(from line: String, policy: String) -> String? {
        if line.hasPrefix("||") {
            let host = normalizeHost(String(line.dropFirst(2)))
            guard isPlausibleHost(host) else { return nil }
            return "DOMAIN-SUFFIX,\(host),\(policy)"
        }
        if line.hasPrefix("|") {
            let rest = String(line.dropFirst())
            if let host = hostFromURLPrefix(rest), isPlausibleHost(host) {
                return "DOMAIN,\(host),\(policy)"
            }
            return nil
        }
        if line.hasPrefix("/"), line.hasSuffix("/"), line.count > 2 {
            let pattern = String(line.dropFirst().dropLast())
            guard !pattern.isEmpty else { return nil }
            return "DOMAIN-REGEX,\(pattern),\(policy)"
        }
        let host = normalizeHost(line)
        guard isPlausibleHost(host) else { return nil }
        return "DOMAIN-SUFFIX,\(host),\(policy)"
    }

    private static func hostFromURLPrefix(_ rest: String) -> String? {
        let lower = rest.lowercased()
        let body: String
        if lower.hasPrefix("https://") {
            body = String(rest.dropFirst("https://".count))
        } else if lower.hasPrefix("http://") {
            body = String(rest.dropFirst("http://".count))
        } else {
            body = rest
        }
        let host = body.split(separator: "/", maxSplits: 1).first.map(String.init) ?? body
        return normalizeHost(host)
    }

    private static func normalizeHost(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasPrefix(".") { h = String(h.dropFirst()) }
        if h.hasPrefix("*.") { h = String(h.dropFirst(2)) }
        if h.hasSuffix(".") { h = String(h.dropLast()) }
        if let at = h.firstIndex(of: "/") { h = String(h[..<at]) }
        if let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }
        return h
    }

    private static func isPlausibleHost(_ host: String) -> Bool {
        guard host.count >= 3, host.count <= 253 else { return false }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Cache

    private static func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func saveCache(_ cache: Cache) throws {
        let dir = Paths.supportDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: cacheURL, options: .atomic)
    }
}
