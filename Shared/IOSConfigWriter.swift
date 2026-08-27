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
            turboMode: true,
            domainSniffing: true,
            dnsPreference: dnsPreference
        )
        // Patch DNS listen + TUN flags for NE (auto-route off; fd injected at runtime).
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
        var lines = yaml.components(separatedBy: "\n")
        // Force DNS listen used by NEPacketTunnelNetworkSettings
        for i in lines.indices {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("listen:") {
                // Only replace the DNS listen under dns: block — first listen after dns is enough for our generated YAML.
                if i > 0, lines[i - 1].contains("enable:") || lines[max(0, i - 2)].contains("dns:") {
                    lines[i] = "  listen: \(AppConstants.dnsListen)"
                }
            }
        }
        // Ensure tun auto-route / auto-detect are false (iOS provides routes).
        var out: [String] = []
        var inTun = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("tun:") {
                inTun = true
                out.append(line)
                continue
            }
            if inTun {
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty {
                    inTun = false
                } else if trimmed.hasPrefix("auto-route:") {
                    out.append("  auto-route: false")
                    continue
                } else if trimmed.hasPrefix("auto-detect-interface:") {
                    out.append("  auto-detect-interface: false")
                    continue
                } else if trimmed.hasPrefix("stack:") {
                    out.append("  stack: gvisor")
                    continue
                }
            }
            out.append(line)
        }
        // Prefer fake-ip DNS at 198.18.0.2 style for NE — keep enhanced-mode fake-ip from generator.
        return out.joined(separator: "\n")
    }
}
