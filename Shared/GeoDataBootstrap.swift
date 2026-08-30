import Foundation

/// Prefetch mihomo geo databases into the App Group before VPN starts (avoids NE hang on first connect).
enum GeoDataBootstrap {
    private static let geoipURL = URL(string: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb")!
    private static let geositeURL = URL(string: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat")!

    /// mihomo `-d` home: Mac uses `supportDir`; iOS NE uses `supportDir/mihomo`.
    private static var geoHomeDir: URL {
        #if os(macOS)
        Paths.supportDir
        #else
        Paths.mihomoHomeDir
        #endif
    }

    static var geoipFile: URL { geoHomeDir.appendingPathComponent("geoip.metadb") }
    static var geositeFile: URL { geoHomeDir.appendingPathComponent("geosite.dat") }

    static func isReady() -> Bool {
        let fm = FileManager.default
        guard let geo = try? fm.attributesOfItem(atPath: geoipFile.path)[.size] as? Int64,
              let site = try? fm.attributesOfItem(atPath: geositeFile.path)[.size] as? Int64 else {
            return false
        }
        return geo > 64 * 1024 && site > 64 * 1024
    }

    /// iOS NE: remove geo DBs that trigger GitHub downloads and hang tunnel start.
    static func scrubStaleGeoDatabases() {
        #if os(iOS)
        MihomoConfigCheck.scrubStaleGeoDatabases()
        #endif
    }

    private static let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        #if os(macOS)
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
        ]
        #else
        // iOS: CFNetwork proxy enable constants are unavailable — use string keys.
        config.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0,
        ]
        #endif
        return URLSession(configuration: config)
    }()

    static func ensurePresent(onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        #if os(macOS)
        migrateLegacyGeoIfNeeded()
        #endif
        _ = geoHomeDir
        onProgress?("正在准备 geoip…")
        try await downloadIfNeeded(url: geoipURL, to: geoipFile, label: "geoip")
        onProgress?("正在准备 geosite…")
        try await downloadIfNeeded(url: geositeURL, to: geositeFile, label: "geosite")
        onProgress?("地理库就绪")
    }

    #if os(macOS)
    /// Older builds stored geo DB under supportDir/mihomo; mihomo `-d` uses supportDir.
    private static func migrateLegacyGeoIfNeeded() {
        let fm = FileManager.default
        let legacy = Paths.mihomoHomeDir
        let modern = Paths.supportDir
        for name in ["geoip.metadb", "geosite.dat"] {
            let from = legacy.appendingPathComponent(name)
            let to = modern.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            try? fm.copyItem(at: from, to: to)
        }
    }
    #endif

    private static func downloadIfNeeded(url: URL, to dest: URL, label: String) async throws {
        if let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64,
           size > 64 * 1024 {
            return
        }
        let (tmp, response) = try await directSession.download(from: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "GeoDataBootstrap", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(label) 下载失败"
            ])
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
