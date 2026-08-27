import NetworkExtension
import os

#if canImport(MihomoCore)
import MihomoCore
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyStarted = false
    private var gcTimer: DispatchSourceTimer?
    private let log = OSLog(subsystem: "com.bashx.app.ios", category: "tunnel")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        writeLog("startTunnel")

        #if canImport(MihomoCore)
        let home = Paths.mihomoHomeDir.path
        BridgeSetHomeDir(home)

        let configPath = Paths.mihomoConfigURL.path
        guard FileManager.default.fileExists(atPath: configPath) else {
            completionHandler(TunnelError.configNotFound)
            return
        }

        let settings = makeNetworkSettings()
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                self.writeLog("setTunnelNetworkSettings failed: \(error)")
                completionHandler(error)
                return
            }

            guard let fd = self.tunnelFileDescriptor else {
                self.writeLog("tun fd not found")
                completionHandler(TunnelError.tunFDNotFound)
                return
            }
            self.writeLog("TUN fd=\(fd)")

            DispatchQueue.global(qos: .userInitiated).async {
                var fdErr: NSError?
                BridgeSetTUNFd(fd, &fdErr)
                if let fdErr {
                    self.writeLog("SetTUNFd failed: \(fdErr)")
                    completionHandler(fdErr)
                    return
                }

                var startErr: NSError?
                BridgeStartWithExternalController(AppConstants.externalController, "", &startErr)
                if let startErr {
                    self.writeLog("start failed: \(startErr)")
                    completionHandler(startErr)
                    return
                }

                self.proxyStarted = true
                self.startMemoryManagement()
                self.selectSavedNode()
                self.writeLog("proxy started")
                completionHandler(nil)
            }
        }
        #else
        writeLog("MihomoCore missing — run scripts/build_mihomo_ios.sh")
        completionHandler(TunnelError.coreMissing)
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        gcTimer?.cancel()
        gcTimer = nil
        #if canImport(MihomoCore)
        if proxyStarted {
            BridgeStopProxy()
            proxyStarted = false
        }
        #endif
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
            let payload: [String: Any] = [
                "upload": BridgeGetUploadTraffic(),
                "download": BridgeGetDownloadTraffic()
            ]
            completionHandler?(try? JSONSerialization.data(withJSONObject: payload))
        case "select_node":
            if let name = message["node"] as? String {
                selectSavedNode(name)
            }
            completionHandler?(nil)
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

        let ipv6 = NEIPv6Settings(
            addresses: [AppConstants.tunIPv6Address],
            networkPrefixLengths: [NSNumber(value: AppConstants.tunIPv6PrefixLength)]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: [AppConstants.tunDNS])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = NSNumber(value: AppConstants.defaultMTU)
        return settings
    }

    private var tunnelFileDescriptor: Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        var last: Int32?
        for fd: Int32 in 0...10240 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0,
               String(cString: buf).hasPrefix("utun") {
                last = fd
            }
        }
        return last
    }

    #if canImport(MihomoCore)
    private func startMemoryManagement() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { BridgeForceGC() }
        timer.resume()
        gcTimer = timer
    }

    private func selectSavedNode(_ override: String? = nil) {
        let name = override
            ?? UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.string(forKey: "selectedNode")
        guard let name, !name.isEmpty else { return }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "http://\(AppConstants.externalController)/proxies/PROXY") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                self?.writeLog("select \(name) failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                self?.writeLog("select \(encoded) → \(http.statusCode)")
            }
        }.resume()
    }
    #endif

    private func writeLog(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = Paths.tunnelLogURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
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
