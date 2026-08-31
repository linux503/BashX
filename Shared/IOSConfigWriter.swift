import Foundation

enum IOSConfigWriter {
    /// Scrub geo DBs that make mihomo hang downloading GitHub inside the NE.
    static func scrubStaleGeoDatabases() {
        MihomoConfigCheck.scrubStaleGeoDatabases()
    }

    /// Shared preflight for app / widget / auto-reconnect — keeps WeChat-safe rule mode and a lean config.
    @discardableResult
    static func prepareForConnect() -> Bool {
        scrubStaleGeoDatabases()
        var settings = SettingsStore.load()
        var changed = false
        if settings.proxyMode == .global {
            settings.proxyMode = .rule
            changed = true
        }
        if let sel = settings.selectedNodeName, ClashConfigParser.isPlaceholderNodeName(sel) {
            settings.selectedNodeName = nil
            changed = true
        }
        // Prefer TUN capture for normal connect (HTTP-proxy experiment is opt-in only).
        if !settings.iosTunnelCapture {
            settings.iosTunnelCapture = true
            changed = true
        }
        if changed {
            _ = SettingsStore.save(settings)
        }
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        ud?.set(settings.secret, forKey: "apiSecret")
        ud?.set(settings.proxyMode.rawValue, forKey: "proxyMode")
        ud?.set(true, forKey: AppConstants.iosTunnelCaptureKey)
        let nodes = loadCachedNodes(from: settings)
        guard !nodes.isEmpty else { return false }
        let testable = nodes.filter { ClashConfigParser.isSpeedTestable($0) }
        let usable = testable.isEmpty
            ? nodes.filter { !ClashConfigParser.isPlaceholderNodeName($0.name) }
            : testable
        // If the saved pick is missing from what iOS will export, remapping avoids
        // select→400 / dead PROXY (seen on XR with "懒人" outside the Asia pool).
        let saved = settings.selectedNodeName
        let savedOK = saved.flatMap { name in usable.first(where: { $0.name == name })?.name }
        let pick = savedOK
            ?? usable.first(where: { node in
                ["香港", "HK", "台湾", "TW", "日本", "JP", "新加坡", "SG"]
                    .contains(where: { node.name.localizedCaseInsensitiveContains($0) })
            })?.name
            ?? usable.first?.name
            ?? nodes.first?.name
        if pick != settings.selectedNodeName {
            settings.selectedNodeName = pick
            _ = SettingsStore.save(settings)
        }
        if let pick, let node = nodes.first(where: { $0.name == pick }), !node.server.isEmpty {
            ud?.set(node.server, forKey: AppConstants.selectedNodeServerKey)
            ud?.set(pick, forKey: "selectedNode")
        }
        let rules = RuntimeRules.effective(
            base: settings.rules,
            prepend: settings.rulesPrepend,
            videoAdBlockEnabled: settings.videoAdBlockEnabled,
            enabledPluginIds: settings.enabledPluginIds,
            telegramPushEnabled: settings.iosTelegramPushEnabled
        )
        return write(
            nodes: nodes,
            selectedName: pick,
            mode: .rule,
            rules: rules,
            secret: settings.secret,
            dnsPreference: settings.dnsPreference,
            tunnelCapture: true,
            profileRoot: loadPassthroughProfileRoot(from: settings)
        )
    }

    /// Single enabled Clash YAML with native proxy-groups.
    /// iOS: always nil — airport passthrough strips GEOSITE then breaks DNS/MATCH,
    /// and huge YAML burns NE memory. BashX buildConfig is the supported path.
    static func loadPassthroughProfileRoot(from settings: AppSettings) -> [String: Any]? {
        #if os(iOS)
        return nil
        #else
        let enabled = settings.subscriptions.filter(\.enabled)
        guard enabled.count == 1, let sub = enabled.first else { return nil }
        let url = Paths.subscriptionCacheURL(id: sub.id)
        guard let data = try? Data(contentsOf: url),
              let parsed = try? ClashConfigParser.parse(data),
              ClashConfigParser.isCompleteProfile(parsed.rawRoot) else { return nil }
        return parsed.rawRoot
        #endif
    }

    private static func loadCachedNodes(from settings: AppSettings) -> [ProxyNode] {
        var merged: [ProxyNode] = []
        var seen = Set<String>()
        for sub in settings.subscriptions where sub.enabled {
            let url = Paths.subscriptionCacheURL(id: sub.id)
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? ClashConfigParser.parse(data) else { continue }
            for node in parsed.nodes where seen.insert(node.name).inserted {
                merged.append(node)
            }
        }
        return merged
    }

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
        tunnelCapture: Bool = true,
        profileRoot: [String: Any]? = nil
    ) -> Bool {
        let yaml: String
        if let profileRoot {
            yaml = ClashConfigParser.buildPassthroughConfig(
                from: profileRoot,
                mixedPort: AppConstants.mixedPort,
                controller: AppConstants.externalController,
                secret: secret,
                tunEnabled: tunnelCapture,
                tunStack: "gvisor",
                mode: mode,
                allowLan: false,
                dnsPreference: dnsPreference,
                forIOS: true,
                domainSniffing: true,
                selectedName: selectedName
            )
        } else {
            yaml = ClashConfigParser.buildConfig(
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
        }
        let patched = tunnelCapture ? patchForPacketTunnel(yaml) : patchForProxyOnly(yaml)
        do {
            try patched.write(to: Paths.mihomoConfigURL, atomically: true, encoding: .utf8)
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
