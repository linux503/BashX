import Foundation

/// HTTP / mihomo delay reachability probes.
enum WebsiteProbe {
    struct Target: Identifiable, Sendable, Codable {
        let id: String
        let title: String
        /// Primary probe URL (prefer generate_204 / lightweight endpoints).
        let url: String
        /// Fallback URL if primary fails (rate-limit / block).
        let fallbackURL: String?
        let systemImage: String
        /// mihomo proxy-group for `/proxies/{group}/delay`.
        let proxyGroup: String

        var localizedTitle: String {
            id == "baidu" ? L10n.t("probe.baidu") : title
        }
    }

    enum Status: Equatable, Sendable {
        case idle
        case testing
        case ok(ms: Int)
        case fail(String)

        var label: String {
            switch self {
            case .idle: return "—"
            case .testing: return "…"
            case .ok(let ms): return "\(ms) ms"
            case .fail: return L10n.t("probe.fail")
            }
        }
    }

    /// Lightweight endpoints — avoid full page / Translate API (easy 403/429).
    static let defaults: [Target] = [
        Target(
            id: "google",
            title: "Google",
            url: "https://www.gstatic.com/generate_204",
            fallbackURL: "https://www.google.com/generate_204",
            systemImage: "magnifyingglass.circle.fill",
            proxyGroup: "DIRECT"
        ),
        Target(
            id: "baidu",
            title: "Baidu",
            url: "https://www.baidu.com/favicon.ico",
            fallbackURL: "https://www.baidu.com/",
            systemImage: "character.textbox",
            proxyGroup: "DIRECT"
        ),
        Target(
            id: "github",
            title: "GitHub",
            url: "https://www.githubstatus.com/api/v2/status.json",
            fallbackURL: "https://api.github.com/zen",
            systemImage: "chevron.left.forwardslash.chevron.right",
            proxyGroup: "DIRECT"
        ),
        Target(
            id: "youtube",
            title: "YouTube",
            url: "https://www.youtube.com/generate_204",
            fallbackURL: "https://www.youtube.com/favicon.ico",
            systemImage: "play.rectangle.fill",
            proxyGroup: "DIRECT"
        ),
        Target(
            id: "telegram",
            title: "Telegram",
            url: "https://api.telegram.org",
            fallbackURL: "https://core.telegram.org/",
            systemImage: "paperplane.fill",
            proxyGroup: "DIRECT"
        ),
        Target(
            id: "cloudflare",
            title: "CF",
            url: "https://www.cloudflare.com/cdn-cgi/trace",
            fallbackURL: "https://1.1.1.1/cdn-cgi/trace",
            systemImage: "cloud.fill",
            proxyGroup: "DIRECT"
        ),
    ]

    // MARK: - Via mihomo delay API (most reliable on Mac)

    /// Probe through mihomo's built-in delay test for the target's proxy-group.
    static func probeViaController(
        _ target: Target,
        controller: String,
        secret: String,
        timeoutMs: Int = 8000
    ) async -> Status {
        if let status = await delayAPI(
            group: target.proxyGroup,
            url: target.url,
            controller: controller,
            secret: secret,
            timeoutMs: timeoutMs
        ), case .ok = status {
            return status
        }
        if let fallback = target.fallbackURL,
           let status = await delayAPI(
            group: target.proxyGroup,
            url: fallback,
            controller: controller,
            secret: secret,
            timeoutMs: timeoutMs
           ) {
            return status
        }
        // Last resort: HTTP via mixed-port (if controller delay unavailable).
        return .fail(L10n.t("probe.timeout"))
    }

    static func probeAllViaController(
        controller: String,
        secret: String,
        port: Int,
        targets: [Target] = defaults,
        timeoutMs: Int = 8000
    ) async -> [String: Status] {
        var results: [String: Status] = [:]
        // Cap concurrency — blasting 6 delay tests at once often times out.
        let batchSize = 2
        var index = 0
        while index < targets.count {
            let slice = Array(targets[index..<min(index + batchSize, targets.count)])
            await withTaskGroup(of: (String, Status).self) { group in
                for target in slice {
                    group.addTask {
                        var status = await probeViaController(
                            target,
                            controller: controller,
                            secret: secret,
                            timeoutMs: timeoutMs
                        )
                        if case .fail = status {
                            status = await probeViaMixedPort(target, port: port, timeout: TimeInterval(timeoutMs) / 1000.0)
                        }
                        return (target.id, status)
                    }
                }
                for await (id, status) in group {
                    results[id] = status
                }
            }
            index += batchSize
        }
        return results
    }

    private static func delayAPI(
        group: String,
        url testURL: String,
        controller: String,
        secret: String,
        timeoutMs: Int
    ) async -> Status? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = group.addingPercentEncoding(withAllowedCharacters: allowed) ?? group
        var components = URLComponents(string: "http://\(controller)/proxies/\(encoded)/delay")
        components?.queryItems = [
            URLQueryItem(name: "url", value: testURL),
            URLQueryItem(name: "timeout", value: String(max(timeoutMs, 2000))),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutMs) / 1000.0 + 3)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .fail(L10n.t("probe.noResponse")) }
            if !(200...299).contains(http.statusCode) {
                return .fail("HTTP \(http.statusCode)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .fail(L10n.t("probe.parseFail"))
            }
            let delay: Int? = {
                if let v = json["delay"] as? Int { return v }
                if let v = json["delay"] as? Double { return Int(v.rounded()) }
                if let v = json["delay"] as? NSNumber { return v.intValue }
                return nil
            }()
            guard let delay, delay > 0, delay < 60_000 else {
                return .fail(L10n.t("probe.timeout"))
            }
            let wall = max(delay, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            return .ok(ms: min(delay, wall))
        } catch {
            return .fail(shortError(error))
        }
    }

    // MARK: - Via mixed-port (HTTP CONNECT + SOCKS fallback)

    static func probeViaMixedPort(_ target: Target, port: Int, timeout: TimeInterval = 10) async -> Status {
        let urls = [target.url] + (target.fallbackURL.map { [$0] } ?? [])
        for urlString in urls {
            if let status = await httpViaProxy(urlString: urlString, port: port, timeout: timeout, socks: false),
               case .ok = status {
                return status
            }
            if let status = await httpViaProxy(urlString: urlString, port: port, timeout: timeout, socks: true),
               case .ok = status {
                return status
            }
        }
        return .fail(L10n.t("probe.timeout"))
    }

    static func probeAllViaMixedPort(
        port: Int,
        targets: [Target] = defaults,
        timeout: TimeInterval = 10
    ) async -> [String: Status] {
        var results: [String: Status] = [:]
        await withTaskGroup(of: (String, Status).self) { group in
            for target in targets {
                group.addTask {
                    let status = await probeViaMixedPort(target, port: port, timeout: timeout)
                    return (target.id, status)
                }
            }
            for await (id, status) in group {
                results[id] = status
            }
        }
        return results
    }

    private static func httpViaProxy(
        urlString: String,
        port: Int,
        timeout: TimeInterval,
        socks: Bool
    ) async -> Status? {
        guard let url = URL(string: urlString) else { return .fail(L10n.t("probe.badURL")) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 BashX-Probe/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.httpShouldUsePipelining = false
        #if os(macOS)
        if socks {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        } else {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        }
        #else
        config.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": port,
        ]
        #endif
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse else { return .fail(L10n.t("probe.noResponse")) }
            let ms = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            if acceptableStatus(http.statusCode) {
                return .ok(ms: ms)
            }
            return .fail("HTTP \(http.statusCode)")
        } catch {
            return .fail(shortError(error))
        }
    }

    // MARK: - Via VPN / TUN

    static func probeViaVPN(_ target: Target, timeout: TimeInterval = 12) async -> Status {
        await probeDirect(target, timeout: timeout)
    }

    static func probeAllViaVPN(
        targets: [Target] = defaults,
        timeout: TimeInterval = 12
    ) async -> [String: Status] {
        var results: [String: Status] = [:]
        let batchSize = 2
        var index = 0
        while index < targets.count {
            let slice = Array(targets[index..<min(index + batchSize, targets.count)])
            await withTaskGroup(of: (String, Status).self) { group in
                for target in slice {
                    group.addTask {
                        (target.id, await probeViaVPN(target, timeout: timeout))
                    }
                }
                for await (id, status) in group {
                    results[id] = status
                }
            }
            index += batchSize
        }
        return results
    }

    // MARK: - Direct

    static func probeDirect(_ target: Target, timeout: TimeInterval = 12) async -> Status {
        let urls = [target.url] + (target.fallbackURL.map { [$0] } ?? [])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 BashX-Probe/1.0",
                forHTTPHeaderField: "User-Agent"
            )
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                let ms = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
                if acceptableStatus(http.statusCode) {
                    return .ok(ms: ms)
                }
            } catch {
                continue
            }
        }
        return .fail(L10n.t("probe.timeout"))
    }

    static func probeAllDirect(
        targets: [Target] = defaults,
        timeout: TimeInterval = 12
    ) async -> [String: Status] {
        var results: [String: Status] = [:]
        await withTaskGroup(of: (String, Status).self) { group in
            for target in targets {
                group.addTask {
                    (target.id, await probeDirect(target, timeout: timeout))
                }
            }
            for await (id, status) in group {
                results[id] = status
            }
        }
        return results
    }

    // MARK: - Tunnel JSON

    struct TunnelResult: Codable, Sendable {
        let id: String
        let ok: Bool
        let ms: Int
        let error: String?
    }

    static func status(from tunnel: TunnelResult) -> Status {
        if tunnel.ok, tunnel.ms > 0, tunnel.ms < 60_000 {
            return .ok(ms: tunnel.ms)
        }
        let msg = tunnel.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .fail((msg?.isEmpty == false) ? msg! : L10n.t("probe.timeout"))
    }

    static func payloadForTunnel(targets: [Target] = defaults, timeoutMs: Int = 8000) -> [String: Any] {
        [
            "action": "probe_websites",
            "timeout_ms": timeoutMs,
            "targets": targets.map {
                var row: [String: Any] = [
                    "id": $0.id,
                    "url": $0.url,
                    "proxy": $0.proxyGroup,
                ]
                if let fallback = $0.fallbackURL {
                    row["fallback"] = fallback
                }
                return row
            },
        ]
    }

    static func parseTunnelResponse(_ data: Data) -> [String: Status] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["results"] as? [[String: Any]] else { return [:] }
        var out: [String: Status] = [:]
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            let ok = row["ok"] as? Bool ?? false
            let ms = (row["ms"] as? NSNumber)?.intValue ?? (row["ms"] as? Int) ?? -1
            let err = row["error"] as? String
            out[id] = status(from: TunnelResult(id: id, ok: ok, ms: ms, error: err))
        }
        return out
    }

    /// Connectivity check — 403/429 still means the path works.
    private static func acceptableStatus(_ code: Int) -> Bool {
        if (200...399).contains(code) { return true }
        if [403, 404, 405, 429, 502, 503].contains(code) { return true }
        return false
    }

    private static func shortError(_ error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut: return L10n.t("probe.timeout")
            case .notConnectedToInternet: return L10n.t("probe.noNetwork")
            case .cannotFindHost: return L10n.t("probe.dnsFail")
            case .secureConnectionFailed: return L10n.t("probe.tlsFail")
            default: break
            }
            return urlErr.localizedDescription
        }
        return error.localizedDescription
    }
}
