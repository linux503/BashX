import NetworkExtension
import os
import Darwin

#if canImport(MihomoCore)
import MihomoCore
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?
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

        let settings = makeNetworkSettings()
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
    /// Primary: real utun fd + gVisor (BaoLianDeng) — full TCP/UDP.
    /// Fallback: socketpair + packetFlow + system stack (QUIC-heavy only; TCP often missing in logs).
    private func startEngine(_ completionHandler: @escaping (Error?) -> Void) {
        BridgeUpdateLogLevel("info")

        let bindIF = TunnelInterface.preferredOutboundInterface() ?? ""
        BridgeSetOutboundInterface(bindIF)
        writeLog("outbound bindIF=\(bindIF.isEmpty ? "(none)" : bindIF)")
        writeLog("ifaces \(TunnelInterface.outboundInterfaceDebugLine())")

        let mode: TunnelDataMode
        if let utun = TunnelInterface.scanUtunFD(preferAddress: AppConstants.tunAddress),
           let goFd = TunnelInterface.duplicatedFD(utun) {
            ownedTunFd = goFd
            writeLog("TUN mode=utun-direct fd=\(utun) dup=\(goFd) (primary)")
            mode = .utunDirect(goFd: goFd)
        } else if let pair = TunnelSocketPair.make() {
            writeLog("TUN mode=socketpair+system mihomoFd=\(pair.mihomoFd) bridgeFd=\(pair.bridgeFd) (fallback)")
            mode = .socketpair(pair)
        } else if let utun = TunnelInterface.fileDescriptor(packetFlow: packetFlow),
                  let goFd = TunnelInterface.duplicatedFD(utun) {
            ownedTunFd = goFd
            writeLog("TUN mode=utun-direct-fallback fd=\(utun) source=\(TunnelInterface.fdSource(packetFlow: packetFlow))")
            mode = .utunDirect(goFd: goFd)
        } else {
            writeLog("utun+socketpair both failed errno=\(errno)")
            finish(completionHandler, TunnelError.tunFDNotFound)
            return
        }

        switch mode {
        case .socketpair(let pair):
            startPacketBridge(bridgeFd: pair.bridgeFd)
            applyAndStart(tunFd: pair.mihomoFd, socketpair: true, completionHandler)
        case .utunDirect(let goFd):
            packetBridge = nil
            applyAndStart(tunFd: goFd, socketpair: false, completionHandler)
        }
    }

    private enum TunnelDataMode {
        case utunDirect(goFd: Int32)
        case socketpair(TunnelSocketPair.Pair)
    }

    private func applyAndStart(tunFd: Int32, socketpair: Bool, _ completionHandler: @escaping (Error?) -> Void) {
        BridgeConfigureTUNPath(socketpair)

        var fdErr: NSError?
        if !BridgeSetTUNFd(tunFd, &fdErr) || fdErr != nil {
            let err = fdErr ?? NSError(domain: "BashX", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "SetTUNFd 失败"
            ])
            writeLog("SetTUNFd failed: \(err)")
            finish(completionHandler, err)
            return
        }

        var startErr: NSError?
        let ok = BridgeStartWithExternalController(AppConstants.externalController, "", &startErr)
        if !ok || startErr != nil {
            let err = startErr ?? NSError(domain: "BashX", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "mihomo 启动失败"
            ])
            writeLog("start failed ok=\(ok) err=\(err)")
            finish(completionHandler, err)
            return
        }

        proxyStarted = true
        startMemoryManagement()
        selectSavedNodeWithRetry()
        let path = socketpair ? "socketpair+system" : "utun-direct"
        writeLog("proxy started running=\(BridgeIsRunning()) path=\(path)")
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
        writeLog("stopTunnel reason=\(reason.rawValue)")
        completionHandler()
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
        default:
            completionHandler?(nil)
        }
        #else
        completionHandler?(nil)
        #endif
    }

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        let ipv4 = NEIPv4Settings(addresses: [AppConstants.tunAddress], subnetMasks: [AppConstants.tunSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.ipv6Settings = nil

        let dns = NEDNSSettings(servers: [AppConstants.tunDNS])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
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

    private func startMemoryManagement() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3, repeating: 5)
        timer.setEventHandler { [weak self] in
            BridgeForceGC()
            guard let self else { return }
            let core = "up=\(BridgeGetUploadTraffic()) down=\(BridgeGetDownloadTraffic())"
            if let bridge = self.packetBridge {
                self.writeLog(bridge.statsLine + " " + core)
            } else {
                self.writeLog("utun-direct " + core)
            }
        }
        timer.resume()
        gcTimer = timer
    }

    private func selectSavedNodeWithRetry(_ override: String? = nil) {
        let delays: [TimeInterval] = [0, 0.5, 1.2, 2.5]
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
        guard let url = URL(string: "http://\(AppConstants.externalController)/proxies/PROXY") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.writeLog("select \(name) failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("select \(name) → \(http.statusCode)")
            }
        }.resume()
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": mode])
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.writeLog("set_mode \(mode) failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("set_mode \(mode) → \(http.statusCode)")
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
        try? handle.synchronize()
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
