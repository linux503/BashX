import Foundation

enum CoreHealth {
    /// True when controller API responds (with secret when configured).
    static func apiAlive(controller: String, secret: String) async -> Bool {
        await ClashCore.isRunning(controller: controller, secret: secret)
    }

    /// True when mixed-port accepts TCP.
    static func mixedPortAlive(port: Int) -> Bool {
        PortProbe.isListening(port: port)
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

    /// Current PROXY selection can reach Google (used when auto-picking nodes).
    static func googleReachable(port: Int) async -> Bool {
        if await httpViaProxy(port: port, urlString: "https://www.google.com/generate_204", timeout: 8) {
            return true
        }
        return await httpViaProxy(port: port, urlString: "https://www.gstatic.com/generate_204", timeout: 6)
    }

    /// Telegram API reachable through local mixed-port (SOCKS — same path as Telegram desktop).
    static func telegramReachable(port: Int) async -> Bool {
        if await socksViaProxy(port: port, urlString: TelegramReliability.probeURL, timeout: 8) {
            return true
        }
        return await httpViaProxy(port: port, urlString: TelegramReliability.probeURL, timeout: 8)
    }

    private static func socksViaProxy(port: Int, urlString: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort as String: port,
        ]
        do {
            let (_, response) = try await URLSession(configuration: config).data(for: request)
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
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port
        ]
        do {
            let (_, response) = try await URLSession(configuration: config).data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (200...399).contains(code)
        } catch {
            return false
        }
    }

    static func proxySession(port: Int, timeout: TimeInterval = 8) -> URLSession {
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
        return URLSession(configuration: config)
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
