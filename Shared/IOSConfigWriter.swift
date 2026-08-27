import Foundation

enum IOSConfigWriter {
    /// Write Clash/mihomo YAML for iOS Packet Tunnel.
    /// - `tunnelCapture`: true = TUN+gVisor（全 App）；false = 仅 mixed-port + 系统 HTTP 代理（实验）。
    @discardableResult
    static func write(
        nodes: [ProxyNode],
        selectedName: String?,
        mode: ProxyMode,
        rules: [String],
        secret: String = "",
        dnsPreference: DnsPreference = .smart,
        tunnelCapture: Bool = true
    ) -> Bool {
        let yaml = ClashConfigParser.buildConfig(
            nodes: nodes,
            selectedName: selectedName,
            mixedPort: AppConstants.mixedPort,
            controller: AppConstants.externalController,
            secret: secret,
            rules: rules,
            tunEnabled: tunnelCapture,
            tunStack: "gvisor",
            mode: mode,
            allowLan: false,
            turboMode: false,
            domainSniffing: true,
            dnsPreference: dnsPreference,
            forIOS: true
        )
        let patched = tunnelCapture ? patchForPacketTunnel(yaml) : patchForProxyOnly(yaml)
        do {
            try patched.write(to: Paths.mihomoConfigURL, atomically: true, encoding: .utf8)
            try? patched.write(to: Paths.configURL, atomically: true, encoding: .utf8)
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(tunnelCapture, forKey: AppConstants.iosTunnelCaptureKey)
            return true
        } catch {
            return false
        }
    }

    private static func patchForPacketTunnel(_ yaml: String) -> String {
        var out: [String] = []
        var inTun = false
        var skippingDnsHijackList = false

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("listen:") {
                out.append("  listen: \(AppConstants.dnsListen)")
                continue
            }

            if trimmed.hasPrefix("tun:") {
                inTun = true
                skippingDnsHijackList = false
                out.append(line)
                continue
            }

            if inTun {
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty {
                    inTun = false
                    skippingDnsHijackList = false
                } else if trimmed.hasPrefix("auto-route:") {
                    out.append("  auto-route: false")
                    continue
                } else if trimmed.hasPrefix("auto-detect-interface:") {
                    out.append("  auto-detect-interface: false")
                    continue
                } else if trimmed.hasPrefix("stack:") {
                    out.append("  stack: gvisor")
                    continue
                } else if trimmed.hasPrefix("dns-hijack:") {
                    out.append("  dns-hijack:")
                    out.append("    - \(AppConstants.tunDNS):53")
                    out.append("    - any:53")
                    skippingDnsHijackList = true
                    continue
                } else if skippingDnsHijackList && trimmed.hasPrefix("-") {
                    continue
                } else if skippingDnsHijackList && !trimmed.hasPrefix("-") {
                    skippingDnsHijackList = false
                }
            }

            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// Proxy-only: keep DNS listen on loopback; mixed-port already binds 127.0.0.1 in YAML.
    private static func patchForProxyOnly(_ yaml: String) -> String {
        var out: [String] = []
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("listen:") {
                out.append("  listen: \(AppConstants.dnsListen)")
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
