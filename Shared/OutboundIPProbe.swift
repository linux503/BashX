import Foundation

enum OutboundIPProbe {
    /// Fetch public IP. When `viaProxyPort` is set, go through local mixed-port.
    static func fetch(viaProxyPort: Int? = nil) async -> String? {
        let endpoints = [
            "https://api.ipify.org",
            "https://ifconfig.me/ip",
            "https://icanhazip.com"
        ]
        for urlString in endpoints {
            guard let url = URL(string: urlString) else { continue }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 8
            if let port = viaProxyPort, port > 0 {
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
            }
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty,
                      text.count <= 64 else { continue }
                return text
            } catch {
                continue
            }
        }
        return nil
    }
}
