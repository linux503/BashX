import Foundation

/// Mac TUN app split — ClashFX / ACL4SSR / Clash Verge pattern.
///
/// https://github.com/Clash-FX/cn-apps-direct
/// Process rules MUST sit above MATCH,PROXY or domestic apps get
/// wrapped in the VPN and die.
///
/// AdsPower / SunBrowser: do **not** PROCESS-NAME the whole tree (breaks IPFoxy chain).
/// Control-plane domains go PROXY so Ads「检查代理」/ ip-scan can reach their API.
enum MacAppBypassRules {
    private static let electronSuffixes = [
        " Helper",
        " Helper (GPU)",
        " Helper (Renderer)",
        " Helper (Plugin)",
        " Helper (Alerts)",
        " Helper (Network)",
    ]

    /// Other fingerprint browsers still ship local S5; keep process DIRECT.
    /// AdsPower / SunBrowser use the dedicated rules below so their control-plane
    /// domains can still be proxied before their S5 socket is made DIRECT.
    static let fingerprintRules: [String] = [
        "PROCESS-NAME-REGEX,(?i)(BitBrowser|Hubstudio|MoreLogin|GoLogin|Orbita|Dolphin|Multilogin|Incogniton|VMLogin|Kameleo|IxBrowser|LinxBrowser),DIRECT",
        "PROCESS-PATH-REGEX,(?i)(bitbrowser|hubstudio|morelogin|gologin|orbita|dolphin|multilogin|incogniton|vmlogin|kameleo|ixbrowser),DIRECT",
    ]

    /// AdsPower control plane — must PROXY (not DIRECT).
    /// DIRECT + GEOIP,CN blackholes `ip-scan.adspower.net` / API on many CN ISP paths,
    /// so Ads UI shows「连接测试失败」even when IPFoxy SOCKS itself is fine.
    /// Other full-tunnel VPNs send these overseas; match that behavior.
    static let adsPowerRules: [String] = [
        "DOMAIN-SUFFIX,adspower.net,PROXY",
        "DOMAIN-SUFFIX,adspower.com,PROXY",
        "DOMAIN-SUFFIX,adspowerapp.com,PROXY",
        "DOMAIN-KEYWORD,adspower,PROXY",
        "DOMAIN-SUFFIX,myclientip.com,PROXY",
        "DOMAIN-SUFFIX,wswebpic.com,PROXY",
        "DOMAIN-SUFFIX,data4.net,PROXY",
        "DOMAIN-KEYWORD,ip-scan,PROXY",
    ]

    /// AdsPower connects to the user supplied SOCKS5 endpoint from its browser/helper
    /// processes.  When that endpoint is an IP literal there is no hostname for a
    /// DOMAIN rule to match, so letting it fall through to MATCH,PROXY creates a
    /// second proxy hop (and commonly a loop).  Keep control-plane DOMAIN rules
    /// above these rules, then dial the actual S5 endpoint on the physical network.
    static let adsPowerSocksDirectRules: [String] = [
        "PROCESS-NAME-REGEX,(?i)(AdsPower|SunBrowser)( Helper( \\(GPU\\)| \\(Renderer\\)| \\(Plugin\\)| \\(Alerts\\)| \\(Network\\))?)?,DIRECT",
        "PROCESS-PATH-REGEX,(?i)(adspower|sunbrowser),DIRECT",
    ]

    /// Overseas residential / ISP proxy gates — must beat any leftover process DIRECT.
    static let residentialProxyChainRules: [String] = [
        "DOMAIN-SUFFIX,ipfoxy.com,PROXY",
        "DOMAIN-SUFFIX,ipfoxy.io,PROXY",
        "DOMAIN-KEYWORD,ipfoxy,PROXY",
    ]

    /// Injected first in every Mac yaml (ClashFX "Bypass Common Chinese Apps").
    static let all: [String] = {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ line: String) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return }
            guard seen.insert(t).inserted else { return }
            out.append(t)
        }
        // Chain gates first so DOMAIN match wins over process DIRECT elsewhere.
        residentialProxyChainRules.forEach(add)
        fingerprintRules.forEach(add)
        adsPowerRules.forEach(add)
        adsPowerSocksDirectRules.forEach(add)
        for name in cnProcessNames {
            add("PROCESS-NAME,\(name),DIRECT")
            if !name.contains("Helper") {
                add("PROCESS-PATH,*\(name).app/Contents/MacOS/*,DIRECT")
                for suffix in electronSuffixes {
                    add("PROCESS-NAME,\(name)\(suffix),DIRECT")
                }
            }
        }
        return out
    }()

    static func electronHelperRules(for processName: String, target: String) -> [String] {
        let base = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.localizedCaseInsensitiveContains("Helper") else { return [] }
        let policy = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = policy.isEmpty ? "DIRECT" : policy
        return electronSuffixes.map { "PROCESS-NAME,\(base)\($0),\(t)" }
    }

    /// Clash-FX cn-apps-direct + common Mac CN binaries.
    private static let cnProcessNames: [String] = {
        let bundled = loadBundledProcessNames()
        return bundled.isEmpty ? embeddedProcessNames : bundled
    }()

    private static let embeddedProcessNames: [String] = [
        "WeChat", "Weixin", "WeChatAppEx",
        "QQ", "QQNT", "TIM",
        "WeCom", "企业微信", "wxwork",
        "DingTalk", "Lark", "Feishu",
        "wemeetapp", "TencentMeeting", "TencentMeetingApp",
        "NeteaseMusic", "QQMusic", "KuGou", "KWMusic",
        "哔哩哔哩", "Bilibili", "iQIYI", "Youku", "TencentVideo", "qqlive",
        "Douyin", "抖音",
        "BaiduNetdisk", "aDrive", "QuarkCloudDrive", "Thunder", "ThunderX",
        "OneDrive", "OneDriveUpdater", "Folx", "Transmission", "qBittorrent", "qbittorrent", "uTorrent", "aria2c", "Motrix",
        "wpsoffice", "TencentDocs",
        "Alipay", "支付宝",
        "Meituan", "Eleme", "Taobao", "淘宝",
        "xiaohongshu", "小红书",
        "ToDesk", "SunloginClient", "AnyDesk", "RustDesk",
        "Foxmail", "NeteaseMailMaster", "WeChatDevTools",
    ]

    private static func loadBundledProcessNames() -> [String] {
        let urls: [URL?] = [
            Bundle.main.url(forResource: "mac-apps-direct", withExtension: "list", subdirectory: "rules"),
            Bundle.main.url(forResource: "mac-apps-direct", withExtension: "list", subdirectory: "Resources/rules"),
            Bundle.main.url(forResource: "mac-apps-direct", withExtension: "list"),
        ]
        guard let url = urls.compactMap({ $0 }).first,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var names: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("PROCESS-NAME,") else { continue }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2, !parts[1].isEmpty else { continue }
            names.append(parts[1])
        }
        return names
    }
}
