import Foundation

struct SubscriptionUserInfo: Codable, Hashable {
    var upload: Int64
    var download: Int64
    var total: Int64
    /// Unix seconds; nil means unknown / unlimited.
    var expireAt: Date?

    var used: Int64 { max(0, upload) + max(0, download) }

    var remaining: Int64? {
        guard total > 0 else { return nil }
        return max(0, total - used)
    }

    var usedRatio: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }

    var usedText: String {
        ByteFormat.size(used)
    }

    var remainingText: String {
        if let remaining { return ByteFormat.size(remaining) }
        return total > 0 ? "0 B" : "不限"
    }

    var totalText: String {
        total > 0 ? ByteFormat.size(total) : "不限"
    }

    var expireText: String {
        guard let expireAt else { return "未知" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: expireAt)
    }

    var expireRelativeText: String {
        guard let expireAt else { return "未知" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expireAt).day ?? 0
        if days < 0 { return "已过期" }
        if days == 0 { return "今日到期" }
        if days < 30 { return "剩 \(days) 天" }
        return expireText
    }

    /// Absolute date + relative hint for cards.
    var expireDetailText: String {
        guard let expireAt else { return "未知" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expireAt).day ?? 0
        if days < 0 { return "\(expireText) · 已过期" }
        if days == 0 { return "\(expireText) · 今日" }
        if days < 365 { return "\(expireText) · \(days)天" }
        return expireText
    }

    var isExpired: Bool {
        guard let expireAt else { return false }
        return expireAt < Date()
    }

    /// Clash / Stash / Verge standard:
    /// `upload=123; download=456; total=789; expire=1710000000`
    static func parse(headerRaw: String?) -> SubscriptionUserInfo? {
        guard var raw = headerRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        // Some CDNs percent-encode the header value.
        raw = raw.removingPercentEncoding ?? raw

        var map: [String: Int64] = [:]
        for part in raw.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "&" }) {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let key = piece[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let valueRaw = piece[piece.index(after: eq)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !valueRaw.isEmpty else { continue }
            // Accept plain ints; ignore floats by truncating at decimal.
            let intPart = valueRaw.split(separator: ".").first.map(String.init) ?? valueRaw
            guard let value = Int64(intPart) else { continue }
            map[key] = value
        }

        let upload = map["upload"] ?? 0
        let download = map["download"] ?? 0
        let total = map["total"] ?? 0
        let expireTs = map["expire"]
        guard upload > 0 || download > 0 || total > 0 || (expireTs ?? 0) > 0 else {
            return nil
        }

        let expireAt: Date? = {
            guard let ts = expireTs, ts > 0 else { return nil }
            // Milliseconds vs seconds.
            if ts > 10_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
            }
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }()

        return SubscriptionUserInfo(
            upload: upload,
            download: download,
            total: total,
            expireAt: expireAt
        )
    }

    /// Also accept `# subscription-userinfo: ...` lines inside the body (some converters).
    static func parse(fromBody data: Data) -> SubscriptionUserInfo? {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else { return nil }
        let head = text.prefix(8_192)
        for line in head.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard lower.contains("subscription-userinfo") else { continue }
            if let idx = trimmed.firstIndex(of: ":") {
                let value = trimmed[trimmed.index(after: idx)...]
                    .trimmingCharacters(in: .whitespaces)
                if let info = parse(headerRaw: String(value)) { return info }
            }
            // `# subscription-userinfo upload=...` without colon
            if let range = lower.range(of: "subscription-userinfo") {
                let after = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if let info = parse(headerRaw: String(after)) { return info }
            }
        }
        return nil
    }
}

enum SubscriptionFetchError: LocalizedError {
    case badURL
    case httpStatus(Int)
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .badURL: return "订阅链接无效"
        case .httpStatus(let code): return "服务器返回 HTTP \(code)"
        case .emptyBody: return "订阅内容为空"
        }
    }
}

enum SubscriptionFetcher {
    struct FetchResult {
        let data: Data
        let userInfo: SubscriptionUserInfo?
        let usedUserAgent: String
        /// From `profile-title` / `content-disposition` when present.
        let suggestedName: String?
    }

    /// Providers usually only emit traffic headers when UA contains `clash`.
    private static let userAgents: [String] = [
        "clash.meta",
        "ClashMeta/1.19.0",
        "clash-verge/v2.0.0",
        "ClashX/1.118.0 (com.west2online.ClashX)",
        "ClashforWindows/0.20.39",
        "Stash/3.0.0 Clash/1.18.0",
        "Clash/1.18.0"
    ]

    private static let requestTimeout: TimeInterval = 12
    private static let resourceTimeout: TimeInterval = 20

    /// - Parameter viaProxyPort: when set (e.g. local mixed-port), race/fetch through HTTP proxy
    ///   like Clash Verge `self_proxy` — some airports only reachable via proxy.
    static func fetch(urlString: String, viaProxyPort: Int? = nil) async throws -> FetchResult {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw SubscriptionFetchError.badURL
        }

        let primaryUA = userAgents[0]
        var lastError: Error?

        // Fast path: race direct vs local proxy (first body wins). Do NOT loop UAs just for traffic headers —
        // that used to take up to ~3 minutes when userinfo was missing.
        do {
            if let port = viaProxyPort, port > 0 {
                return try await raceDirectAndProxy(url: url, userAgent: primaryUA, proxyPort: port)
            }
            return try await fetchOnce(url: url, userAgent: primaryUA, proxyPort: nil)
        } catch {
            lastError = error
        }

        // Fallbacks only when the first attempt fully failed (no body).
        if let port = viaProxyPort, port > 0 {
            // Primary already raced; try one alternate UA via proxy then direct.
            for ua in userAgents.dropFirst().prefix(2) {
                do {
                    return try await raceDirectAndProxy(url: url, userAgent: ua, proxyPort: port)
                } catch {
                    lastError = error
                }
            }
        } else {
            for ua in userAgents.dropFirst().prefix(2) {
                do {
                    return try await fetchOnce(url: url, userAgent: ua, proxyPort: nil)
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError ?? URLError(.badServerResponse)
    }

    /// Whichever path returns a body first wins; cancel the other.
    private static func raceDirectAndProxy(url: URL, userAgent: String, proxyPort: Int) async throws -> FetchResult {
        try await withThrowingTaskGroup(of: FetchResult.self) { group in
            group.addTask {
                try await fetchOnce(url: url, userAgent: userAgent, proxyPort: nil)
            }
            group.addTask {
                try await fetchOnce(url: url, userAgent: userAgent, proxyPort: proxyPort)
            }

            var lastError: Error?
            while let result = await group.nextResult() {
                switch result {
                case .success(let value):
                    group.cancelAll()
                    return value
                case .failure(let error):
                    if (error as? URLError)?.code != .cancelled {
                        lastError = error
                    }
                }
            }
            throw lastError ?? URLError(.cannotConnectToHost)
        }
    }

    private static func fetchOnce(url: URL, userAgent: String, proxyPort: Int?) async throws -> FetchResult {
        try Task.checkCancellation()

        let capture = RedirectHeaderCapture()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "*/*"
        ]
        if let port = proxyPort, port > 0 {
            // Force traffic through local mixed-port (HTTP CONNECT for HTTPS).
            #if os(macOS)
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort as String: port
            ]
            #else
            config.connectionProxyDictionary = [
                "HTTPEnable": true,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": port,
                "HTTPSEnable": true,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": port
            ]
            #endif
        } else {
            // Avoid inheriting a half-dead system proxy that points at another client.
            config.connectionProxyDictionary = [:]
        }

        let session = URLSession(configuration: config, delegate: capture, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        // Some panels key off this (Clash Verge also sends it).
        request.setValue("true", forHTTPHeaderField: "profile-update-interval")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SubscriptionFetchError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else {
            throw SubscriptionFetchError.emptyBody
        }
        // Cap body to avoid memory blow-ups from malicious / misconfigured servers.
        let maxBytes = 20 * 1024 * 1024
        let expected = http.expectedContentLength
        if expected > 0, expected > maxBytes {
            throw URLError(.dataLengthExceedsMaximum)
        }
        guard data.count <= maxBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }

        let headerRaw = extractUserInfoHeader(from: http)
            ?? capture.subscriptionUserInfo

        let userInfo = SubscriptionUserInfo.parse(headerRaw: headerRaw)
            ?? SubscriptionUserInfo.parse(fromBody: data)
        let suggestedName = extractProfileName(from: http)

        return FetchResult(
            data: data,
            userInfo: userInfo,
            usedUserAgent: userAgent,
            suggestedName: suggestedName
        )
    }

    /// `profile-title` (base64 or plain) / `content-disposition` filename.
    static func extractProfileName(from http: HTTPURLResponse) -> String? {
        if let raw = http.value(forHTTPHeaderField: "profile-title")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw.lowercased().hasPrefix("base64:") {
                let b64 = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if let data = Data(base64Encoded: b64),
                   let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return text
                }
            } else {
                return raw
            }
        }
        if let cd = http.value(forHTTPHeaderField: "content-disposition") {
            // filename*=UTF-8''... or filename="..."
            if let range = cd.range(of: "filename\\*=(?:UTF-8''|utf-8'')([^;]+)", options: .regularExpression) {
                var value = String(cd[range])
                if let eq = value.firstIndex(of: "=") {
                    value = String(value[value.index(after: eq)...])
                    if value.lowercased().hasPrefix("utf-8''") {
                        value = String(value.dropFirst(7))
                    }
                    value = value.removingPercentEncoding ?? value
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if !value.isEmpty { return value.replacingOccurrences(of: ".yaml", with: "")
                        .replacingOccurrences(of: ".yml", with: "") }
                }
            }
            if let range = cd.range(of: "filename=\"([^\"]+)\"", options: .regularExpression)
                ?? cd.range(of: "filename=([^;\\s]+)", options: .regularExpression) {
                var value = String(cd[range])
                if let eq = value.firstIndex(of: "=") {
                    value = String(value[value.index(after: eq)...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if !value.isEmpty {
                        return value
                            .replacingOccurrences(of: ".yaml", with: "")
                            .replacingOccurrences(of: ".yml", with: "")
                    }
                }
            }
        }
        return nil
    }

    /// Clash Verge accepts `subscription-userinfo` and CDN meta prefixes:
    /// `x-amz-meta-subscription-userinfo`, `x-obs-meta-…`, `x-cos-meta-…`
    static func extractUserInfoHeader(from http: HTTPURLResponse) -> String? {
        for (key, value) in http.allHeaderFields {
            let name: String
            if let s = key as? String {
                name = s
            } else if let s = key as? NSString {
                name = s as String
            } else {
                continue
            }
            let lower = name.lowercased()
            let matched: Bool = {
                if lower == "subscription-userinfo" { return true }
                if let prefix = lower.stripSuffix("subscription-userinfo") {
                    return prefix.isEmpty || prefix.hasSuffix("-") || prefix.hasSuffix("_")
                }
                return false
            }()
            guard matched else { continue }

            if let text = value as? String, !text.isEmpty { return text }
            if let text = value as? NSString, text.length > 0 { return text as String }
            if let arr = value as? [Any] {
                let joined = arr.compactMap { $0 as? String }.joined(separator: "; ")
                if !joined.isEmpty { return joined }
            }
        }
        // Direct accessors (case-insensitive).
        for key in ["subscription-userinfo", "Subscription-Userinfo", "Subscription-UserInfo"] {
            if let value = http.value(forHTTPHeaderField: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private extension String {
    func stripSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }
}

/// Capture `subscription-userinfo` from redirect hops (some airports only set it there).
private final class RedirectHeaderCapture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _subscriptionUserInfo: String?

    var subscriptionUserInfo: String? {
        lock.lock(); defer { lock.unlock() }
        return _subscriptionUserInfo
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let raw = SubscriptionFetcher.extractUserInfoHeader(from: response) {
            lock.lock()
            _subscriptionUserInfo = raw
            lock.unlock()
        }
        completionHandler(request)
    }
}
