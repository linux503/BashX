import NetworkExtension
import os
import Darwin

#if canImport(MihomoCore)
import MihomoCore
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?
    private var gcTickCount = 0
    private var packetBridge: PacketFlowBridge?
    private var ownedTunFd: Int32 = -1
    private let log = OSLog(subsystem: "com.bashx.app.ios", category: "tunnel")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Fresh log each connect — easier to diagnose "connected but no net".
        try? FileManager.default.removeItem(at: Paths.tunnelLogURL)
        writeLog("startTunnel begin")

        #if canImport(MihomoCore)
        var logErr: NSError?
        BridgeSetLogFile(Paths.tunnelLogURL.path, &logErr)
        if let logErr {
            writeLog("SetLogFile warn: \(logErr.localizedDescription)")
        }

        let home = Paths.mihomoHomeDir.path
        BridgeSetHomeDir(home)
        writeLog("home=\(home) appGroup=\(Paths.usesAppGroup)")

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

        let settings = makeNetworkSettings(tunnelCapture: Self.loadTunnelCapture())
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                self.writeLog("setTunnelNetworkSettings failed: \(error)")
                self.finish(completionHandler, error)
                return
            }
            self.startEngine(completionHandler)
        }
        #else
        writeLog("MihomoCore missing — run scripts/build_mihomo_ios.sh")
        finish(completionHandler, TunnelError.coreMissing)
        #endif
    }

    #if canImport(MihomoCore)
    /// iOS 18+：必须 socketpair + packetFlow 桥；utun 直读收不到 App 包（Stash 新版用 Darwin Tun + 自有桥）。
    private func startEngine(_ completionHandler: @escaping (Error?) -> Void) {
        BridgeUpdateLogLevel("info")

        let tunnelCapture = Self.loadTunnelCapture()
        let bindIF = TunnelInterface.preferredOutboundInterface() ?? ""
        BridgeSetOutboundInterface(bindIF)
        writeLog("outbound bindIF=\(bindIF.isEmpty ? "(none)" : bindIF)")
        writeLog("ifaces \(TunnelInterface.outboundInterfaceDebugLine())")

        guard tunnelCapture else {
            writeLog("TUN mode=off proxy-only mixed-port=\(AppConstants.mixedPort)")
            packetBridge = nil
            applyAndStart(tunFd: -1, socketpair: false, completionHandler)
            return
        }

        guard let pair = TunnelSocketPair.make() else {
            writeLog("socketpair failed errno=\(errno)")
            finish(completionHandler, TunnelError.tunFDNotFound)
            return
        }
        writeLog("TUN mode=socketpair+gvisor mihomoFd=\(pair.mihomoFd) bridgeFd=\(pair.bridgeFd)")
        startPacketBridge(bridgeFd: pair.bridgeFd)
        applyAndStart(tunFd: pair.mihomoFd, socketpair: true, completionHandler)
    }

    private enum TunnelDataMode {
        case socketpair(TunnelSocketPair.Pair)
    }

    private func applyAndStart(tunFd: Int32, socketpair: Bool, _ completionHandler: @escaping (Error?) -> Void) {
        BridgeConfigureTUNPath(socketpair)

        if tunFd >= 0 {
            var fdErr: NSError?
            if !BridgeSetTUNFd(tunFd, &fdErr) || fdErr != nil {
                let err = fdErr ?? NSError(domain: "BashX", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "SetTUNFd 失败"
                ])
                writeLog("SetTUNFd failed: \(err)")
                finish(completionHandler, err)
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
            finish(completionHandler, err)
            return
        }
        writeLog("api secret=\(apiSecret.isEmpty ? "off" : "on")")

        proxyStarted = true
        startMemoryManagement()
        selectSavedNodeWithRetry()
        let path: String = {
            if tunFd < 0 { return "proxy-only" }
            return socketpair ? "socketpair+gvisor" : "utun-direct+gvisor"
        }()
        writeLog("proxy started running=\(BridgeIsRunning()) path=\(path)")
        // Proxy-only: re-assert NEProxySettings after mixed-port is listening.
        if tunFd < 0 {
            let settings = makeNetworkSettings(tunnelCapture: false)
            setTunnelNetworkSettings(settings) { [weak self] error in
                if let error {
                    self?.writeLog("re-apply proxy settings failed: \(error.localizedDescription)")
                } else {
                    self?.writeLog("re-apply proxy settings ok (127.0.0.1:\(AppConstants.mixedPort))")
                }
            }
        }
        finish(completionHandler, nil)

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runConnectivityDiagnostics()
        }
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

    private func makeNetworkSettings(tunnelCapture: Bool) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        if tunnelCapture {
            let ipv4 = NEIPv4Settings(addresses: [AppConstants.tunAddress], subnetMasks: [AppConstants.tunSubnetMask])
            ipv4.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4
            settings.ipv6Settings = nil

            let dns = NEDNSSettings(servers: [AppConstants.tunDNS])
            dns.matchDomains = [""]
            settings.dnsSettings = dns
        } else {
            // HTTP 代理实验：不全量接管路由。
            // 代理必须指向 127.0.0.1（不进 utun/packetFlow）；不要把 198.18.0.1 放进 includedRoutes，
            // 否则系统把发往代理的 TCP 灌进 packetFlow，而本模式不跑桥 → 黑洞。
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

        settings.mtu = NSNumber(value: AppConstants.defaultMTU)
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
                        let proxy = row["proxy"] as? String ?? "PROXY"
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

    private func startMemoryManagement() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 12, repeating: 60)
        timer.setEventHandler { [weak self] in
            BridgeForceGC()
            guard let self else { return }
            self.gcTickCount += 1
            let core = "up=\(BridgeGetUploadTraffic()) down=\(BridgeGetDownloadTraffic()) running=\(BridgeIsRunning())"
            // Disk log at most every ~5 min; os_log every tick is enough for debugging.
            if self.gcTickCount.isMultiple(of: 5) {
                if let bridge = self.packetBridge {
                    self.writeLog(bridge.statsLine + " " + core)
                } else {
                    self.writeLog("proxy-only " + core)
                }
            }
            if self.proxyStarted, !BridgeIsRunning() {
                self.writeLog("mihomo stopped unexpectedly — cancelling tunnel")
                TunnelDiagnostics.recordFailure("核心异常退出（可能内存不足）")
                self.cancelTunnelWithError(
                    NSError(domain: "BashX", code: -10, userInfo: [
                        NSLocalizedDescriptionKey: "核心异常退出，请重连"
                    ])
                )
            }
        }
        timer.resume()
        gcTimer = timer
    }

    private func selectSavedNodeWithRetry(_ override: String? = nil) {
        let delays: [TimeInterval] = [0, 1.2]
        for delay in delays {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.selectSavedNode(override)
            }
        }
    }

    private func selectSavedNode(_ override: String? = nil) {
        let name = override
            ?? UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.string(forKey: "selectedNode")
        guard let name, !name.isEmpty else { return }
        // rule → PROXY; global → GLOBAL；两边都同步，避免切全局后仍走 DIRECT。
        selectGroupProxy(group: "PROXY", name: name)
        selectGroupProxy(group: "GLOBAL", name: name)
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

    private func selectGroupProxy(group: String, name: String) {
        let encoded = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies/\(encoded)") else { return }
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
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("select \(group)→\(name) → \(http.statusCode)")
            }
        }.resume()
    }

    private static func fetchMenuProxyGroups() async -> [[String: Any]] {
        var out: [[String: Any]] = []
        for name in ["GOOGLE", "TELEGRAM", "AUTO"] {
            guard let info = await fetchProxyGroup(name) else { continue }
            out.append(info)
        }
        return out
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
