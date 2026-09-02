import NetworkExtension
import Network
import os
import Darwin

#if canImport(MihomoCore)
import MihomoCore
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?
    private var keepaliveTimer: DispatchSourceTimer?
    private var gcTickCount = 0
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "bashx.tunnel.path", qos: .utility)
    private var packetBridge: PacketFlowBridge?
    private var ownedTunFd: Int32 = -1
    private let log = OSLog(subsystem: "com.bashx.app.ios", category: "tunnel")
    private let logQueue = DispatchQueue(label: "bashx.tunnel.log", qos: .utility)
    private var lastOutboundIF: String = ""
    private var lastPathCloseAt: Date = .distantPast
    private var lastConnCloseAt: Date = .distantPast
    /// Require consecutive dead-core ticks before cancel — single false read caused flap loops.
    private var coreDeadStreak = 0
    private var healInFlight = false
    /// Avoid flipping PROXY leaf every few seconds (Binance WS dies → looks like VPN reconnect).
    private var lastHealSwitchAt: Date = .distantPast
    private var lastHealOkAt: Date = .distantPast

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Keep prior session tail for diagnosing abrupt jetsam kills.
        writeLog("——— session begin ———")

        #if canImport(MihomoCore)
        var logErr: NSError?
        BridgeSetLogFile(Paths.tunnelLogURL.path, &logErr)
        if let logErr {
            writeLog("SetLogFile warn: \(logErr.localizedDescription)")
        }

        let home = Paths.mihomoHomeDir.path
        BridgeSetHomeDir(home)
        writeLog("home=\(home) appGroup=\(Paths.usesAppGroup)")

        // Drop stale group selections only when corrupted — wiping every start forced
        // full re-heal and spiked RSS right after On-Demand restart (jetsam death loop).
        let cacheURL = Paths.mihomoHomeDir.appendingPathComponent("cache.db")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 8 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: cacheURL)
            writeLog("scrubbed oversized cache.db (\(size.intValue / 1024)KB)")
        }

        let configPath = Paths.mihomoConfigURL.path
        guard FileManager.default.fileExists(atPath: configPath) else {
            writeLog("config missing at \(configPath)")
            finish(completionHandler, TunnelError.configNotFound)
            return
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: configPath)[.size] as? Int64 {
            writeLog("config size=\(size)")
        }
        logConfigHints(configPath)
        logGeoFiles()
        // Broken / mismatched geo files make mihomo try GitHub download during Parse and hang the NE.
        scrubStaleGeoDatabases()

        // Start mihomo BEFORE setTunnelNetworkSettings — otherwise default-route + DNS hijack
        // go live while the core is still parsing config (WeChat / all apps lose network).
        let tunnelCapture = Self.loadTunnelCapture()
        bootCore(tunnelCapture: tunnelCapture) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.finish(completionHandler, err)
            case .success(let pendingBridgeFd):
                let settings = self.makeNetworkSettings(tunnelCapture: tunnelCapture)
                self.setTunnelNetworkSettings(settings) { error in
                    if let error {
                        self.writeLog("setTunnelNetworkSettings failed: \(error)")
                        self.finish(completionHandler, error)
                        return
                    }
                    if pendingBridgeFd >= 0 {
                        self.startPacketBridge(bridgeFd: pendingBridgeFd)
                    }
                    self.finish(completionHandler, nil)
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.runConnectivityDiagnostics()
                    }
                }
            }
        }
        #else
        writeLog("MihomoCore missing — run scripts/build_mihomo_ios.sh")
        finish(completionHandler, TunnelError.coreMissing)
        #endif
    }

    #if canImport(MihomoCore)
    /// Bring up mihomo (DNS + mixed-port + TUN fd) before NE routes traffic into the tunnel.
    private func bootCore(tunnelCapture: Bool, completion: @escaping (Result<Int32, Error>) -> Void) {
        BridgeUpdateLogLevel("warning")

        let bindIF = TunnelInterface.preferredOutboundInterface() ?? ""
        BridgeSetOutboundInterface(bindIF)
        writeLog("outbound bindIF=\(bindIF.isEmpty ? "(none)" : bindIF)")
        writeLog("ifaces \(TunnelInterface.outboundInterfaceDebugLine())")

        guard tunnelCapture else {
            writeLog("TUN mode=off proxy-only mixed-port=\(AppConstants.mixedPort)")
            packetBridge = nil
            startCoreOnly(tunFd: -1, socketpair: false, pendingBridgeFd: -1, completion: completion)
            return
        }

        guard let pair = TunnelSocketPair.make() else {
            writeLog("socketpair failed errno=\(errno)")
            completion(.failure(TunnelError.tunFDNotFound))
            return
        }
        writeLog("TUN mode=socketpair+gvisor mihomoFd=\(pair.mihomoFd) bridgeFd=\(pair.bridgeFd) (bridge deferred until NE routes live)")
        startCoreOnly(tunFd: pair.mihomoFd, socketpair: true, pendingBridgeFd: pair.bridgeFd, completion: completion)
    }

    private func startCoreOnly(
        tunFd: Int32,
        socketpair: Bool,
        pendingBridgeFd: Int32,
        completion: @escaping (Result<Int32, Error>) -> Void
    ) {
        BridgeConfigureTUNPath(socketpair)

        if tunFd >= 0 {
            var fdErr: NSError?
            if !BridgeSetTUNFd(tunFd, &fdErr) || fdErr != nil {
                let err = fdErr ?? NSError(domain: "BashX", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "SetTUNFd 失败"
                ])
                writeLog("SetTUNFd failed: \(err)")
                completion(.failure(err))
                return
            }
        } else {
            writeLog("SetTUNFd skipped (proxy-only)")
        }

        var startErr: NSError?
        let apiSecret = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "apiSecret")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ok = BridgeStartWithExternalController(AppConstants.externalController, apiSecret, &startErr)
        if !ok || startErr != nil {
            let err = startErr ?? NSError(domain: "BashX", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "mihomo 启动失败"
            ])
            writeLog("start failed ok=\(ok) err=\(err)")
            completion(.failure(err))
            return
        }
        writeLog("api secret=\(apiSecret.isEmpty ? "off" : "on")")

        proxyStarted = true
        startNetworkMonitor()
        startMemoryManagement()
        startKeepalive()
        selectSavedNodeWithRetry()
        let path: String = {
            if tunFd < 0 { return "proxy-only" }
            return socketpair ? "socketpair+gvisor" : "utun-direct+gvisor"
        }()
        writeLog("core ready running=\(BridgeIsRunning()) path=\(path)")
        completion(.success(pendingBridgeFd))
    }

    private func startPacketBridge(bridgeFd: Int32) {
        let bridge = PacketFlowBridge(packetFlow: packetFlow, bridgeFd: bridgeFd)
        bridge.start()
        packetBridge = bridge
        writeLog("packetFlow bridge started bridgeFd=\(bridgeFd)")
    }

    private func runConnectivityDiagnostics() {
        let tcp = BridgeTestDirectTCP("www.baidu.com", 80) ?? "nil"
        writeLog("DIAG tcp-direct: \(tcp)")
        let dns = BridgeTestDNSResolver(AppConstants.dnsListen) ?? "nil"
        writeLog("DIAG dns: \(dns)")
        if let bridge = packetBridge {
            writeLog("DIAG \(bridge.statsLine)")
        }
        writeLog("DIAG core up=\(BridgeGetUploadTraffic()) down=\(BridgeGetDownloadTraffic())")
    }
    #endif

    private func finish(_ completionHandler: @escaping (Error?) -> Void, _ error: Error?) {
        if let error {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            TunnelDiagnostics.recordFailure(msg)
            writeLog("tunnel failed: \(msg)")
        } else {
            TunnelDiagnostics.recordSuccess()
        }
        if Thread.isMainThread {
            completionHandler(error)
        } else {
            DispatchQueue.main.async { completionHandler(error) }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        gcTimer?.cancel()
        gcTimer = nil
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        packetBridge?.stop()
        packetBridge = nil
        #if canImport(MihomoCore)
        if proxyStarted {
            BridgeStopProxy()
            proxyStarted = false
        }
        #endif
        if ownedTunFd >= 0 {
            close(ownedTunFd)
            ownedTunFd = -1
        }
        let reasonText = Self.stopReasonLabel(reason)
        writeLog("stopTunnel reason=\(reason.rawValue) (\(reasonText))")
        TunnelDiagnostics.recordStop(reason: reason.rawValue, label: reasonText)
        completionHandler()
    }

    private static func stopReasonLabel(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none: return "none"
        case .userInitiated: return "user"
        case .providerFailed: return "providerFailed"
        case .noNetworkAvailable: return "noNetwork"
        case .unrecoverableNetworkChange: return "networkChange"
        case .providerDisabled: return "disabled"
        case .authenticationCanceled: return "authCanceled"
        case .configurationFailed: return "configFailed"
        case .idleTimeout: return "idleTimeout"
        case .configurationDisabled: return "configDisabled"
        case .configurationRemoved: return "configRemoved"
        case .superceded: return "superceded"
        case .userLogout: return "logout"
        case .userSwitch: return "userSwitch"
        case .connectionFailed: return "connectionFailed"
        case .sleep: return "sleep"
        case .appUpdate: return "appUpdate"
        @unknown default: return "unknown(\(reason.rawValue))"
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let action = message["action"] as? String else {
            completionHandler?(nil)
            return
        }

        #if canImport(MihomoCore)
        switch action {
        case "get_traffic":
            let bridge = packetBridge?.trafficTotals()
            let coreUp = BridgeGetUploadTraffic()
            let coreDown = BridgeGetDownloadTraffic()
            let up = max(bridge?.upload ?? 0, coreUp)
            let down = max(bridge?.download ?? 0, coreDown)
            let payload: [String: Any] = [
                "upload": up,
                "download": down
            ]
            completionHandler?(try? JSONSerialization.data(withJSONObject: payload))
        case "select_node":
            if let name = message["node"] as? String {
                selectSavedNode(name)
            }
            completionHandler?(nil)
        case "select_group":
            if let group = message["group"] as? String,
               let name = message["node"] as? String {
                selectGroupProxy(group: group, name: name)
            }
            completionHandler?(nil)
        case "get_proxy_groups":
            Task {
                let groups = await Self.fetchMenuProxyGroups()
                completionHandler?(try? JSONSerialization.data(withJSONObject: ["groups": groups]))
            }
        case "set_mode":
            if let mode = message["mode"] as? String {
                patchProxyMode(mode)
            }
            completionHandler?(nil)
        case "get_log":
            let text = TunnelLogReader.lastLines(TunnelLogReader.defaultLineCount)
            completionHandler?(text.data(using: .utf8))
        case "get_outbound_ip":
            Task {
                let ip = await Self.probeOutboundIP()
                completionHandler?(ip?.data(using: .utf8))
            }
        case "probe_websites":
            let timeoutMs = (message["timeout_ms"] as? NSNumber)?.intValue
                ?? (message["timeout_ms"] as? Int)
                ?? 8000
            let rows = message["targets"] as? [[String: Any]] ?? []
            Task {
                let results = await Self.probeWebsites(rows: rows, timeoutMs: max(timeoutMs, 1000))
                completionHandler?(try? JSONSerialization.data(withJSONObject: ["results": results]))
            }
        case "test_delays":
            // Clash Verge / Stash style: URLTest each leaf via mihomo /proxies/{name}/delay.
            let timeoutMs = (message["timeout_ms"] as? NSNumber)?.intValue
                ?? (message["timeout_ms"] as? Int)
                ?? 5000
            let concurrency = (message["concurrency"] as? NSNumber)?.intValue
                ?? (message["concurrency"] as? Int)
                ?? 4
            let rawURL = (message["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let testURL = rawURL.isEmpty ? "http://www.gstatic.com/generate_204" : rawURL
            let names = message["names"] as? [String] ?? []
            Task {
                let results = await Self.testProxyDelays(
                    names: names,
                    testURL: testURL,
                    timeoutMs: max(timeoutMs, 2000),
                    concurrency: max(1, min(concurrency, 8))
                )
                completionHandler?(try? JSONSerialization.data(withJSONObject: ["results": results]))
            }
        default:
            completionHandler?(nil)
        }
        #else
        completionHandler?(nil)
        #endif
    }

    private static func loadTunnelCapture() -> Bool {
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if ud?.object(forKey: AppConstants.iosTunnelCaptureKey) == nil { return true }
        return ud?.bool(forKey: AppConstants.iosTunnelCaptureKey) ?? true
    }

    /// Domestic CDN bypass — shared list with mihomo route-exclude-address (WeChat/淘宝/抖音 video).
    private static let domesticBypassRoutes: [NEIPv4Route] = DomesticBypassRoutes.neIPv4Routes().map {
        NEIPv4Route(destinationAddress: $0.address, subnetMask: $0.mask)
    }

    /// Telegram DC IPv6 prefixes (clients dial these literals; must enter TUN).
    private static let telegramIPv6Routes: [NEIPv6Route] = [
        NEIPv6Route(destinationAddress: "2001:67c:4e8::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2001:b28:f23c::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2001:b28:f23d::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2001:b28:f23f::", networkPrefixLength: 48),
    ]

    /// Apple APNs IPv6 — without these, Happy-Eyeballs tries physical v6 first and stalls pushes.
    private static let apnsIPv6Routes: [NEIPv6Route] = [
        NEIPv6Route(destinationAddress: "2620:149:a44::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2403:300:a42::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2403:300:a51::", networkPrefixLength: 48),
        NEIPv6Route(destinationAddress: "2a01:b740:a42::", networkPrefixLength: 48),
    ]

    private static func loadTelegramPushEnabled() -> Bool {
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if ud?.object(forKey: AppConstants.iosTelegramPushKey) != nil {
            return ud?.bool(forKey: AppConstants.iosTelegramPushKey) ?? true
        }
        return true
    }

    private func makeNetworkSettings(tunnelCapture: Bool) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = NSNumber(value: AppConstants.defaultMTU)

        if tunnelCapture {
            let ipv4 = NEIPv4Settings(addresses: [AppConstants.tunAddress], subnetMasks: [AppConstants.tunSubnetMask])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            // Domestic CDN off utun — WeChat/淘宝/抖音 video otherwise jetsam the NE (~50MB).
            // TikTok overseas CDN is NOT in douyinChinaBypassRoutes (byteoversea stays in-tunnel).
            ipv4.excludedRoutes = Self.domesticBypassRoutes
            settings.ipv4Settings = ipv4
            // Keep most IPv6 on the physical path (WeChat media CDN). Pull Telegram DC +
            // (when enabled) APNs IPv6 into TUN — otherwise Happy-Eyeballs hangs on blocked v6.
            let ipv6 = NEIPv6Settings(addresses: ["fd00:beef::1"], networkPrefixLengths: [64])
            var v6Routes = Self.telegramIPv6Routes
            if Self.loadTelegramPushEnabled() {
                v6Routes.append(contentsOf: Self.apnsIPv6Routes)
            }
            ipv6.includedRoutes = v6Routes
            settings.ipv6Settings = ipv6

            let dns = NEDNSSettings(servers: [AppConstants.tunDNS])
            dns.matchDomains = [""]
            settings.dnsSettings = dns
        } else {
            // HTTP 代理实验：不全量接管路由（≠ TUN）。
            // 仅覆盖遵循系统 HTTP(S) 代理的流量；UDP/QUIC/大量 App 不会进入代理。
            let ipv4 = NEIPv4Settings(
                addresses: [AppConstants.tunAddress],
                subnetMasks: ["255.255.255.255"]
            )
            ipv4.includedRoutes = []
            settings.ipv4Settings = ipv4
            settings.ipv6Settings = nil
            // 不设 dnsSettings：系统 DNS；HTTPS CONNECT 由 mihomo 解析。

            let proxy = NEProxySettings()
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            proxy.httpServer = NEProxyServer(address: "127.0.0.1", port: AppConstants.mixedPort)
            proxy.httpsServer = NEProxyServer(address: "127.0.0.1", port: AppConstants.mixedPort)
            proxy.matchDomains = nil
            proxy.excludeSimpleHostnames = true
            proxy.exceptionList = [
                "localhost",
                "127.0.0.1",
                "*.local",
                "10.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16",
            ]
            settings.proxySettings = proxy
        }

        return settings
    }

    #if canImport(MihomoCore)
    private static func probeOutboundIP() async -> String? {
        let urls = [
            "https://api.ipify.org",
            "https://ifconfig.me/ip",
            "https://icanhazip.com"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty, text.count <= 64 else { continue }
                return text
            } catch {
                continue
            }
        }
        return nil
    }

    /// Batch URLTest through each leaf proxy (Clash Verge /delay semantics).
    private static func testProxyDelays(
        names: [String],
        testURL: String,
        timeoutMs: Int,
        concurrency: Int
    ) async -> [[String: Any]] {
        guard !names.isEmpty else { return [] }
        var out: [[String: Any]] = []
        out.reserveCapacity(names.count)
        let urls = [
            testURL,
            "http://www.gstatic.com/generate_204",
            "http://cp.cloudflare.com/generate_204",
        ]
        var uniqueURLs: [String] = []
        for u in urls where !u.isEmpty && !uniqueURLs.contains(u) {
            uniqueURLs.append(u)
        }

        var index = 0
        let batch = max(1, concurrency)
        while index < names.count {
            let slice = Array(names[index..<min(index + batch, names.count)])
            await withTaskGroup(of: [String: Any].self) { group in
                for name in slice {
                    group.addTask {
                        var delay = -1
                        for url in uniqueURLs {
                            let (ok, ms, _) = await mihomoDelay(proxy: name, testURL: url, timeoutMs: timeoutMs)
                            if ok, ms > 0 {
                                delay = ms
                                break
                            }
                        }
                        return ["name": name, "delay": delay]
                    }
                }
                for await item in group {
                    out.append(item)
                }
            }
            index += batch
        }
        return out
    }

    /// mihomo `/proxies/{group}/delay` — runs inside NE (same path as user traffic).
    private static func probeWebsites(rows: [[String: Any]], timeoutMs: Int) async -> [[String: Any]] {
        var out: [[String: Any]] = []
        let batchSize = 2
        var index = 0
        while index < rows.count {
            let slice = Array(rows[index..<min(index + batchSize, rows.count)])
            await withTaskGroup(of: [String: Any].self) { group in
                for row in slice {
                    group.addTask {
                        let id = row["id"] as? String ?? ""
                        let url = row["url"] as? String ?? ""
                        let fallback = row["fallback"] as? String
                        // Always DIRECT — website chips must not consume PROXY bandwidth / path.
                        let proxy = "DIRECT"
                        var (ok, ms, err) = await mihomoDelay(proxy: proxy, testURL: url, timeoutMs: timeoutMs)
                        if !ok, let fallback, !fallback.isEmpty {
                            (ok, ms, err) = await mihomoDelay(proxy: proxy, testURL: fallback, timeoutMs: timeoutMs)
                        }
                        return [
                            "id": id,
                            "ok": ok,
                            "ms": ms,
                            "error": err ?? "",
                        ]
                    }
                }
                for await item in group {
                    out.append(item)
                }
            }
            index += batchSize
        }
        return out
    }

        private static func mihomoDelay(proxy: String, testURL: String, timeoutMs: Int) async -> (Bool, Int, String?) {
        let name = proxy.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxy
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 19090
        components.percentEncodedPath = "/proxies/\(name)/delay"
        components.queryItems = [
            URLQueryItem(name: "timeout", value: String(max(timeoutMs, 1000))),
            URLQueryItem(name: "url", value: testURL),
        ]
        guard let reqURL = components.url else { return (false, -1, "URL 无效") }
        var request = URLRequest(url: reqURL, timeoutInterval: TimeInterval(timeoutMs) / 1000 + 4)
        if let secret = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.string(forKey: "apiSecret"),
           !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await localAPISession().data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, -1, "无响应") }
            guard (200...299).contains(http.statusCode) else {
                return (false, -1, "HTTP \(http.statusCode)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (false, -1, "解析失败")
            }
            let delay: Int = {
                if let v = json["delay"] as? Int { return v }
                if let v = json["delay"] as? Double { return Int(v.rounded()) }
                if let v = json["delay"] as? NSNumber { return v.intValue }
                return -1
            }()
            if delay <= 0 || delay >= 65535 { return (false, delay, "不可达") }
            return (true, delay, nil)
        } catch {
            return (false, -1, error.localizedDescription)
        }
    }

    private func startNetworkMonitor() {
        // Seed so the first path callback does not look like an interface flip.
        lastOutboundIF = TunnelInterface.preferredOutboundInterface() ?? ""
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            let bindIF = TunnelInterface.preferredOutboundInterface() ?? ""
            BridgeSetOutboundInterface(bindIF)
            guard let self else { return }
            let previous = self.lastOutboundIF
            let changed = !bindIF.isEmpty && !previous.isEmpty && bindIF != previous
            if !bindIF.isEmpty { self.lastOutboundIF = bindIF }
            self.writeLog("path update bindIF=\(bindIF.isEmpty ? "(none)" : bindIF) changed=\(changed) (no closeAll)")
            // Intentionally do NOT DELETE /connections — that is Binance「网络线路中断」.
        }
        monitor.start(queue: pathQueue)
        pathMonitor = monitor
    }

    private func closeAllConnectionsBestEffort() {
        guard let url = URL(string: "http://\(AppConstants.externalController)/connections") else { return }
        var req = URLRequest(url: url, timeoutInterval: 2)
        req.httpMethod = "DELETE"
        if let secret = apiSecretHeader() {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        Self.localAPISession().dataTask(with: req).resume()
    }

    private func startMemoryManagement() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // Jetsam ~50MB. Baseline NE RSS is often 50–70MB — do NOT closeAll on that
        // (was killing Telegram MTProto every 8s → "Telegram 没网").
        timer.schedule(deadline: .now() + 8, repeating: 12)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.gcTickCount += 1
            let footprint = Self.residentMemoryBytes()
            #if canImport(MihomoCore)
            // Jetsam ~50MB. Baseline NE RSS is often 30–45MB with trading apps.
            // NEVER DELETE /connections under memory pressure — that is exactly the
            // Binance「网络线路中断」storm. Prefer GC; if jetsam kills us, On-Demand restarts.
            if footprint > 18 * 1024 * 1024 {
                BridgeForceGC()
            }
            if footprint > 40 * 1024 * 1024, self.gcTickCount.isMultiple(of: 2) {
                BridgeForceGC()
                self.writeLog("mem high rss=\(footprint / 1024)KB — GC only (keep WS)")
            }
            #endif
            if self.gcTickCount.isMultiple(of: 5) {
                let core = "up=\(BridgeGetUploadTraffic()) down=\(BridgeGetDownloadTraffic()) running=\(BridgeIsRunning()) rss=\(footprint / 1024)KB"
                if let bridge = self.packetBridge {
                    self.writeLog(bridge.statsLine + " " + core)
                } else {
                    self.writeLog("proxy-only " + core)
                }
            }
            if self.proxyStarted, !BridgeIsRunning() {
                self.writeLog("WARN mihomo running=false (unexpected)")
            }
        }
        timer.resume()
        gcTimer = timer
    }

    /// Periodic activity so iOS does not idle-timeout the tunnel.
    /// Local API alone is NOT enough — NE idle looks at packetFlow traffic.
    private func startKeepalive() {
        keepaliveTimer?.cancel()
        coreDeadStreak = 0
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // ~20s: stay under NE idle without waking the core too often (RSS).
        timer.schedule(deadline: .now() + 10, repeating: 20)
        timer.setEventHandler { [weak self] in
            guard let self, self.proxyStarted else { return }
            #if canImport(MihomoCore)
            if !BridgeIsRunning() {
                self.coreDeadStreak += 1
                self.writeLog("keepalive: mihomo running=false streak=\(self.coreDeadStreak)")
                // Do NOT cancelTunnel — that + On-Demand was a flap loop.
                // Leave the NE up; system/On-Demand handles truly dead providers.
                return
            }
            self.coreDeadStreak = 0
            #endif
            // 1) Touch local API (cheap health check).
            if let url = URL(string: "http://\(AppConstants.externalController)/version") {
                var req = URLRequest(url: url, timeoutInterval: 3)
                req.httpMethod = "GET"
                if let secret = self.apiSecretHeader() {
                    req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                }
                Self.localAPISession().dataTask(with: req).resume()
            }
            // 2) Always inject a tiny TUN DNS packet — skipping this under Douyin RSS
            //    used to cause idleTimeout right when video paused / app backgrounded.
            self.packetBridge?.injectDNSKeepalive(to: AppConstants.tunDNS)
            // Extra NWConnection pulse only when RSS is comfortable (avoids socket churn).
            if Self.residentMemoryBytes() <= 30 * 1024 * 1024 {
                self.pulseTunnelDNS()
            }
        }
        timer.resume()
        keepaliveTimer = timer
    }

    /// UDP DNS query routed into the tunnel so NE sees outbound packets.
    private func pulseTunnelDNS() {
        let host = NWEndpoint.Host(AppConstants.tunDNS)
        let connection = NWConnection(host: host, port: 53, using: .udp)
        connection.start(queue: pathQueue)
        // Minimal DNS query for "." (root) — 17 bytes.
        let query = Data([
            0xBE, 0xEF, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x01
        ])
        connection.send(content: query, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    override func wake() {
        writeLog("wake — reassert keepalive")
        #if canImport(MihomoCore)
        if proxyStarted {
            let bindIF = TunnelInterface.preferredOutboundInterface() ?? ""
            BridgeSetOutboundInterface(bindIF)
            startKeepalive()
            if !BridgeIsRunning() {
                writeLog("wake: core not running")
            }
        }
        #endif
    }

    private func selectSavedNodeWithRetry(_ override: String? = nil) {
        let delays: [TimeInterval] = [0, 1.2]
        for delay in delays {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.selectSavedNode(override)
            }
        }
        // Heal quickly — waiting 3s left XR on a dead leaf with no proxy path.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.healDeadSelectedNode()
        }
    }

    private func selectSavedNode(_ override: String? = nil) {
        let name = override
            ?? UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.string(forKey: "selectedNode")
        guard let name, !name.isEmpty else { return }
        // rule → PROXY; global → GLOBAL；两边都同步，避免切全局后仍走 DIRECT。
        selectGroupProxy(group: "PROXY", name: name) { [weak self] code in
            // Missing from config (400) — fail over immediately.
            if code == 400 || code == 404 {
                self?.healDeadSelectedNode()
            }
        }
        selectGroupProxy(group: "GLOBAL", name: name)
        selectGroupProxy(group: "GOOGLE", name: name)
        selectGroupProxy(group: "TELEGRAM", name: name)
        // Prefer Asia leaf for TIKTOK when the user picked one; else leave group default (JP/PROXY).
        let asiaHints = ["日本", "JP", "Japan", "新加坡", "SG", "香港", "HK", "台湾", "台灣", "TW"]
        if asiaHints.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
            selectGroupProxy(group: "TIKTOK", name: name)
        } else {
            selectGroupProxy(group: "TIKTOK", name: "PROXY")
        }
    }

    /// If the pinned leaf cannot dial (vmess timeout / 502), try other PROXY members.
    /// Conservative enough not to thrash trading WS, but dead leaves must not stick for minutes.
    private func healDeadSelectedNode() {
        if healInFlight { return }
        // After a real switch, cool down — false flips kill Binance / HTX WebSockets.
        if Date().timeIntervalSince(lastHealSwitchAt) < 120 { return }
        // Under memory pressure delay probes often false-fail — skip heal entirely.
        if Self.residentMemoryBytes() > 42 * 1024 * 1024 {
            writeLog("heal skipped (rss high)")
            return
        }
        healInFlight = true
        Task { [weak self] in
            defer { self?.healInFlight = false }
            guard let self else { return }
            let preferred = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .string(forKey: "selectedNode") ?? ""
            let testURL = "https://www.gstatic.com/generate_204"
            if !preferred.isEmpty {
                // Require three failed probes before switching.
                var lastErr: String?
                for attempt in 1...3 {
                    let (ok, ms, err) = await Self.mihomoDelay(proxy: preferred, testURL: testURL, timeoutMs: 6000)
                    if ok {
                        self.lastHealOkAt = Date()
                        self.writeLog("heal node OK \(preferred) \(ms)ms (try \(attempt))")
                        return
                    }
                    lastErr = err
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                    }
                }
                self.writeLog("heal node FAIL \(preferred): \(lastErr ?? "?") — trying alternates")
            }
            let candidates = await self.fetchProxyGroupMembers(group: "PROXY")
            let ordered = Self.prioritizeAsiaNodes(candidates, excluding: preferred)
            for name in ordered.prefix(4) {
                let (ok, ms, _) = await Self.mihomoDelay(proxy: name, testURL: testURL, timeoutMs: 5000)
                guard ok else { continue }
                self.writeLog("heal switched → \(name) \(ms)ms")
                self.lastHealSwitchAt = Date()
                self.selectSavedNode(name)
                UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                    .set(name, forKey: "selectedNode")
                return
            }
            self.writeLog("heal: no working PROXY leaf found")
        }
    }

    private func fetchProxyGroupMembers(group: String) async -> [String] {
        let encoded = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies/\(encoded)") else {
            return []
        }
        var req = URLRequest(url: url, timeoutInterval: 4)
        if let secret = apiSecretHeader() {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await Self.localAPISession().data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            return (json["all"] as? [String]) ?? []
        } catch {
            return []
        }
    }

    private static func prioritizeAsiaNodes(_ names: [String], excluding: String) -> [String] {
        let skip: Set<String> = [
            excluding, "DIRECT", "REJECT", "PROXY", "GLOBAL", "COMPATIBLE",
            "AUTO", "BALANCE", "FALLBACK", "GOOGLE", "TELEGRAM", "APNS",
        ]
        let keys = ["香港", "HK", "Hong Kong", "台湾", "TW", "日本", "JP", "新加坡", "SG"]
        let leaves = names.filter { !skip.contains($0) && !$0.hasPrefix("♻️") && !$0.hasPrefix("🚀") }
        let asia = leaves.filter { n in keys.contains(where: { n.localizedCaseInsensitiveContains($0) }) }
        let rest = leaves.filter { n in !asia.contains(n) }
        return asia + rest
    }

    private func apiSecretHeader() -> String? {
        let secret = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "apiSecret")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return secret.isEmpty ? nil : secret
    }

    /// Local API must not go through system/NE HTTP proxy (proxy-only mode loop).
    private static func localAPISession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }

    private func selectGroupProxy(group: String, name: String, completion: ((Int) -> Void)? = nil) {
        let encoded = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies/\(encoded)") else {
            completion?(-1)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = apiSecretHeader() {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        Self.localAPISession().dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.writeLog("select \(group)→\(name) failed: \(error.localizedDescription)")
                completion?(-1)
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("select \(group)→\(name) → \(http.statusCode)")
                completion?(http.statusCode)
            } else {
                completion?(-1)
            }
        }.resume()
    }

    private static func fetchMenuProxyGroups() async -> [[String: Any]] {
        if let all = await fetchAllPolicyGroups(), !all.isEmpty {
            return all
        }
        // Fallback: fixed names (older cores / partial API).
        var out: [[String: Any]] = []
        for name in AppConstants.menuProxyGroups {
            guard let info = await fetchProxyGroup(name) else { continue }
            out.append(info)
        }
        return out
    }

    /// All Selector/URLTest/Fallback/LoadBalance groups from `GET /proxies`.
    private static func fetchAllPolicyGroups() async -> [[String: Any]]? {
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        let secret = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "apiSecret")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await localAPISession().data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = json["proxies"] as? [String: Any] else {
            return nil
        }

        var byName: [String: [String: Any]] = [:]
        for (name, value) in proxies {
            if AppConstants.isInternalProxyGroupName(name) { continue }
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String,
                  AppConstants.selectableProxyGroupTypes.contains(type) else { continue }
            let all = (dict["all"] as? [String]) ?? []
            guard !all.isEmpty else { continue }
            byName[name] = [
                "name": name,
                "type": type,
                "now": dict["now"] as? String ?? "",
                "all": all,
            ]
        }
        guard !byName.isEmpty else { return nil }
        return AppConstants.orderedProxyGroupNames(Array(byName.keys)).compactMap { byName[$0] }
    }

    private static func fetchProxyGroup(_ group: String) async -> [String: Any]? {
        let encoded = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies/\(encoded)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        let secret = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "apiSecret")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await localAPISession().data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let now = json["now"] as? String ?? ""
        let all = (json["all"] as? [String]) ?? []
        guard !all.isEmpty else { return nil }
        return [
            "name": group,
            "type": json["type"] as? String ?? "",
            "now": now,
            "all": all,
        ]
    }

    private func patchProxyMode(_ mode: String) {
        let allowed: Set<String> = ["rule", "global", "direct"]
        guard allowed.contains(mode) else {
            writeLog("set_mode ignored invalid=\(mode)")
            return
        }
        guard let url = URL(string: "http://\(AppConstants.externalController)/configs") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = apiSecretHeader() {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": mode])
        Self.localAPISession().dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                self.writeLog("set_mode \(mode) failed: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            self.writeLog("set_mode \(mode) → \(code)")
            // rule/global：同步 PROXY+GLOBAL 出口；切模式后关掉旧连接，避免串线。
            if mode != "direct" {
                self.selectSavedNode()
            }
            self.closeAllConnections()
            self.verifyProxyMode(expected: mode)
        }.resume()
    }

    private func verifyProxyMode(expected: String) {
        guard let url = URL(string: "http://\(AppConstants.externalController)/configs") else { return }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        if let secret = apiSecretHeader() {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        Self.localAPISession().dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mode = (json["mode"] as? String)?.lowercased() else {
                self?.writeLog("set_mode verify skipped (no mode field)")
                return
            }
            if mode == expected {
                self?.writeLog("set_mode verified=\(mode)")
            } else {
                self?.writeLog("set_mode MISMATCH expected=\(expected) got=\(mode)")
            }
        }.resume()
    }

    private func closeAllConnections() {
        guard let url = URL(string: "http://\(AppConstants.externalController)/connections") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let secret = apiSecretHeader() {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        Self.localAPISession().dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.writeLog("close connections failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("close connections → \(http.statusCode)")
            }
        }.resume()
    }
    #endif

    private func logConfigHints(_ path: String) {
        guard let yaml = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let listen = yaml.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("listen:") } ?? "?"
        let autoDetect = yaml.split(separator: "\n").first { $0.contains("auto-detect-interface") } ?? "?"
        writeLog("config hint \(listen.trimmingCharacters(in: .whitespaces)) | \(autoDetect.trimmingCharacters(in: .whitespaces))")
    }

    private func logGeoFiles() {
        for name in ["geoip.metadb", "geosite.dat", "country.mmdb"] {
            let path = Paths.mihomoHomeDir.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? -1
            writeLog("\(name) size=\(size)")
        }
    }

    /// Drop mismatched geo DBs so mihomo won't block on "MMDB invalid → download GitHub".
    private func scrubStaleGeoDatabases() {
        let fm = FileManager.default
        let home = Paths.mihomoHomeDir
        // iOS rules/DNS do not need geo DBs; any leftover metadb/mmdb is a hang risk.
        for name in ["geoip.metadb", "geosite.dat", "country.mmdb", "GeoLite2-Country.mmdb"] {
            let url = home.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
                writeLog("scrubbed \(name)")
            }
        }
    }

    private func writeLog(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
        let line = "[\(Self.logStamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        logQueue.async {
            let url = Paths.tunnelLogURL
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
                return
            }
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue > TunnelLogReader.maxFileBytes {
                let keep = TunnelLogReader.lastLines(200)
                try? (keep + "\n" + line).write(to: url, atomically: true, encoding: .utf8)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? data.write(to: url, options: .atomic)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    private static func logStamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

enum TunnelError: LocalizedError {
    case configNotFound
    case tunFDNotFound
    case coreMissing

    var errorDescription: String? {
        switch self {
        case .configNotFound: return "未找到 config.yaml，请先在 App 内更新订阅"
        case .tunFDNotFound: return "无法获取 TUN 文件描述符"
        case .coreMissing: return "缺少 MihomoCore，请先运行 scripts/build_mihomo_ios.sh"
        }
    }
}
