import Foundation

enum IOSConfigWriter {
    /// Write Clash/mihomo YAML tailored for iOS Packet Tunnel (fd-injected TUN).
    @discardableResult
    static func write(
        nodes: [ProxyNode],
        selectedName: String?,
        mode: ProxyMode,
        rules: [String],
        secret: String = "",
        dnsPreference: DnsPreference = .smart
    ) -> Bool {
        let yaml = ClashConfigParser.buildConfig(
            nodes: nodes,
            selectedName: selectedName,
            mixedPort: AppConstants.mixedPort,
            controller: AppConstants.externalController,
            secret: secret,
            rules: rules,
            tunEnabled: true,
            tunStack: "gvisor",
            mode: mode,
            allowLan: false,
            turboMode: false,
            domainSniffing: true,
            dnsPreference: dnsPreference,
            forIOS: true
        )
        let patched = patchForPacketTunnel(yaml)
        do {
            try patched.write(to: Paths.mihomoConfigURL, atomically: true, encoding: .utf8)
            try? patched.write(to: Paths.configURL, atomically: true, encoding: .utf8)
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

            // DNS listen: never bind 198.18.0.2 (fails); use localhost (BaoLianDeng).
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
}
