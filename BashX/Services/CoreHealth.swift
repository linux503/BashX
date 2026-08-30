import Foundation

enum CoreHealth {
    /// Short TTL so SwiftUI / health loops don't re-block on TCP connect every read.
    private static let portCacheLock = NSLock()
    private static var portCache: [Int: (alive: Bool, at: CFAbsoluteTime)] = [:]
    private static let portCacheTTL: CFAbsoluteTime = 0.45

    /// True when controller API responds (with secret when configured).
    static func apiAlive(controller: String, secret: String) async -> Bool {
        await ClashCore.isRunning(controller: controller, secret: secret)
    }

    /// True when mixed-port accepts TCP. Cached ~0.45s to avoid main-thread stalls.
    static func mixedPortAlive(port: Int) -> Bool {
        guard port > 0, port <= 65535 else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        portCacheLock.lock()
        if let cached = portCache[port], now - cached.at < portCacheTTL {
            let alive = cached.alive
            portCacheLock.unlock()
            return alive
        }
        portCacheLock.unlock()

        let alive = PortProbe.isListening(port: port)
        portCacheLock.lock()
        portCache[port] = (alive, now)
        // Bound cache size (port churn during migrate).
        if portCache.count > 64 {
            let cutoff = now - 5
            portCache = portCache.filter { $0.value.at >= cutoff }
        }
        portCacheLock.unlock()
        return alive
    }

    /// Non-blocking for @MainActor callers — probe off the UI thread.
    static func mixedPortAliveAsync(port: Int) async -> Bool {
        await Task.detached(priority: .utility) {
            mixedPortAlive(port: port)
        }.value
    }

    static func invalidatePortCache(port: Int? = nil) {
        portCacheLock.lock()
        if let port {
            portCache.removeValue(forKey: port)
        } else {
            portCache.removeAll(keepingCapacity: true)
        }
        portCacheLock.unlock()
    }

    /// Running config has TUN enabled (nil if API unreachable).
    static func tunEnabled(controller: String, secret: String) async -> Bool? {
        guard let url = URL(string: "http://\(controller)/configs") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let tun = json["tun"] as? [String: Any] {
            if let enable = tun["enable"] as? Bool { return enable }
            // Some mihomo builds encode bool-ish values as 0/1.
            if let n = tun["enable"] as? NSNumber { return n.boolValue }
        }
        return false
    }

    /// Poll until TUN is on. Treats API `nil` as transient (do not fail early).
    static func waitUntilTunEnabled(
        controller: String,
        secret: String,
        attempts: Int = 20,
        intervalNanoseconds: UInt64 = 250_000_000
    ) async -> Bool {
        for _ in 0..<attempts {
            if await tunEnabled(controller: controller, secret: secret) == true {
                return true
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return await tunEnabled(controller: controller, secret: secret) == true
    }

    /// Local proxy stack OK: mixed-port can reach a domestic URL (no selector mutation).
    static func proxyPathHealthy(port: Int, controller: String, secret: String) async -> Bool {
        _ = controller
        _ = secret
        return await httpViaProxy(port: port, urlString: "https://www.baidu.com/", timeout: 5)
    }

    /// Current GOOGLE group can reach Translate API (not just generate_204).
    static func googleReachable(port: Int) async -> Bool {
        if await httpViaProxy(port: port, urlString: GoogleReliability.probeURL, timeout: 10) {
            return true
        }
        if await httpViaProxy(port: port, urlString: GoogleReliability.fallbackProbeURL, timeout: 8) {
            return true
        }
        return await httpViaProxy(port: port, urlString: "https://www.gstatic.com/generate_204", timeout: 6)
    }

    /// Telegram API reachable through local mixed-port (SOCKS — same path as Telegram desktop).
    static func telegramReachable(port: Int) async -> Bool {
        if await socksViaProxy(port: port, urlString: TelegramReliability.probeURL, timeout: 8) {
            return true
        }
        if await httpViaProxy(port: port, urlString: TelegramReliability.probeURL, timeout: 8) {
            return true
        }
        return await httpViaProxy(port: port, urlString: TelegramReliability.fallbackProbeURL, timeout: 8)
    }

    /// Cursor cloud reachable through local mixed-port (IDE + agent HTTPS streams).
    static func cursorReachable(port: Int) async -> Bool {
        if await httpViaProxy(port: port, urlString: CursorReliability.probeURL, timeout: 10) {
            return true
        }
        if await relaxedHttpViaProxy(port: port, urlString: CursorReliability.fallbackProbeURL, timeout: 8) {
            return true
        }
        return await relaxedHttpViaProxy(
            port: port,
            urlString: "https://marketplace.cursorapi.com",
            timeout: 8
        )
    }

    private static let proxySessionLock = NSLock()
    private static var httpProxySessions: [Int: URLSession] = [:]
    private static var socksProxySessions: [Int: URLSession] = [:]

    private static func httpProxySession(port: Int, timeout: TimeInterval) -> URLSession {
        proxySessionLock.lock()
        defer { proxySessionLock.unlock() }
        if let existing = httpProxySessions[port] { return existing }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 4
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port
        ]
        let session = URLSession(configuration: config)
        httpProxySessions[port] = session
        if httpProxySessions.count > 8 {
            httpProxySessions.removeValue(forKey: httpProxySessions.keys.sorted().first!)
        }
        return session
    }

    private static func socksProxySession(port: Int, timeout: TimeInterval) -> URLSession {
        proxySessionLock.lock()
        defer { proxySessionLock.unlock() }
        if let existing = socksProxySessions[port] { return existing }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 4
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort as String: port,
        ]
        let session = URLSession(configuration: config)
        socksProxySessions[port] = session
        if socksProxySessions.count > 8 {
            socksProxySessions.removeValue(forKey: socksProxySessions.keys.sorted().first!)
        }
        return session
    }

    private static func socksViaProxy(port: Int, urlString: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        do {
            let (_, response) = try await socksProxySession(port: port, timeout: timeout).data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // api.telegram.org returns 404/302 without a bot token — still proves routing works.
            return (200...499).contains(code)
        } catch {
            return false
        }
    }

    private static func httpViaProxy(port: Int, urlString: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        do {
            let (_, response) = try await httpProxySession(port: port, timeout: timeout).data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (200...399).contains(code)
        } catch {
            return false
        }
    }

    /// API endpoints may return 401/404 without auth — still proves routing works.
    private static func relaxedHttpViaProxy(port: Int, urlString: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        do {
            let (_, response) = try await httpProxySession(port: port, timeout: timeout).data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (200...499).contains(code)
        } catch {
            return false
        }
    }

    static func proxySession(port: Int, timeout: TimeInterval = 8) -> URLSession {
        httpProxySession(port: port, timeout: timeout)
    }
}

/// Resolve current egress IP through BashX mixed-port.
enum OutboundIPProbe {
    private static let endpoints = [
        "https://api.ipify.org?format=json",
        "https://api64.ipify.org?format=json",
        "https://ifconfig.me/ip",
    ]

    static func fetch(port: Int) async -> String? {
        let session = CoreHealth.proxySession(port: port, timeout: 8)
        for urlString in endpoints {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue("BashX/1.0", forHTTPHeaderField: "User-Agent")
            if let ip = await parse(session: session, request: request), isPlausibleIP(ip) {
                return ip
            }
        }
        return nil
    }

    private static func parse(session: URLSession, request: URLRequest) async -> String? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = json["ip"] as? String {
                return ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) }
        } catch {
            return nil
        }
    }

    private static func isPlausibleIP(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (7...45).contains(s.count) else { return false }
        if s.contains(":") {
            return s.filter { $0 == ":" }.count >= 2
        }
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), n >= 0, n <= 255 else { return false }
            return true
        }
    }
}
