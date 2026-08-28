import Foundation

/// App UI language. Default follows the system locale.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zh
    case en

    var id: String { rawValue }

    /// Fixed bilingual labels so the picker stays readable in either language.
    var pickerTitle: String {
        switch self {
        case .system: return "System · 跟随系统"
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// Resolved catalog code used by `L10n`.
    var code: String {
        switch self {
        case .zh: return "zh"
        case .en: return "en"
        case .system:
            let id = Locale.current.language.languageCode?.identifier ?? "en"
            return id.hasPrefix("zh") ? "zh" : "en"
        }
    }

    /// Last applied language for non-SwiftUI call sites (status text, enums).
    static var current: AppLanguage = .system
}

/// Lightweight zh/en string table. Views should pass `settings.uiLanguage` so SwiftUI refreshes.
enum L10n {
    static func t(_ key: String, _ language: AppLanguage = .current) -> String {
        let code = language.code
        if let row = table[key] {
            return row[code] ?? row["zh"] ?? key
        }
        return key
    }

    static func apply(_ language: AppLanguage) {
        AppLanguage.current = language
    }

    private static let table: [String: [String: String]] = [
        // Tabs
        "tab.home": ["zh": "首页", "en": "Home"],
        "tab.nodes": ["zh": "节点", "en": "Nodes"],
        "tab.subscriptions": ["zh": "订阅", "en": "Subscriptions"],
        "tab.settings": ["zh": "设置", "en": "Settings"],

        // Common
        "common.on": ["zh": "开", "en": "On"],
        "common.off": ["zh": "关", "en": "Off"],
        "common.done": ["zh": "完成", "en": "Done"],
        "common.cancel": ["zh": "取消", "en": "Cancel"],
        "common.copy": ["zh": "复制", "en": "Copy"],
        "common.none": ["zh": "无", "en": "None"],
        "common.loading": ["zh": "查询中…", "en": "Loading…"],
        "common.running": ["zh": "运行中", "en": "Running"],
        "common.stopped": ["zh": "未启动", "en": "Stopped"],
        "common.connecting": ["zh": "连接中…", "en": "Connecting…"],

        // Language
        "lang.title": ["zh": "语言", "en": "Language"],
        "lang.footer": [
            "zh": "切换后界面立即生效。",
            "en": "UI updates immediately after switching.",
        ],
        "lang.changed.zh": ["zh": "已切换为中文", "en": "Switched to Chinese"],
        "lang.changed.en": ["zh": "已切换为 English", "en": "Switched to English"],
        "lang.changed.system": ["zh": "已跟随系统语言", "en": "Following system language"],

        // Proxy mode
        "proxy.rule": ["zh": "规则", "en": "Rule"],
        "proxy.global": ["zh": "全局", "en": "Global"],
        "proxy.direct": ["zh": "直连", "en": "Direct"],
        "proxy.rule.sub": ["zh": "按规则分流：国内直连，国外走代理", "en": "Route by rules: domestic direct, foreign via proxy"],
        "proxy.global.sub": ["zh": "全部流量走当前节点（忽略规则）", "en": "All traffic via current node (ignore rules)"],
        "proxy.direct.sub": ["zh": "全部流量直连，不走代理", "en": "All traffic direct, no proxy"],

        // Appearance / nodes
        "appearance.light": ["zh": "浅色", "en": "Light"],
        "appearance.dark": ["zh": "深色", "en": "Dark"],
        "nodes.card": ["zh": "卡片", "en": "Cards"],
        "nodes.list": ["zh": "列表", "en": "List"],

        // DNS
        "dns.smart": ["zh": "智能分流", "en": "Smart"],
        "dns.domestic": ["zh": "国内优选", "en": "Domestic"],
        "dns.foreign": ["zh": "国外优选", "en": "Foreign"],
        "dns.smart.sub": [
            "zh": "国内站走阿里/腾讯 DoH，国外站自动回落 Cloudflare/Google（默认）",
            "en": "CN sites use Ali/Tencent DoH; foreign falls back to Cloudflare/Google",
        ],
        "dns.domestic.sub": [
            "zh": "默认使用国内 DNS，国外域名再回落海外解析，适合日常国内浏览",
            "en": "Prefer domestic DNS; foreign domains fall back overseas",
        ],
        "dns.foreign.sub": [
            "zh": "默认使用 Cloudflare/Google，国内域名走专用国内 DNS，适合海外节点为主",
            "en": "Prefer Cloudflare/Google; CN domains use domestic DNS",
        ],

        // iOS Settings sections
        "ios.settings.nav": ["zh": "设置", "en": "Settings"],
        "ios.sec.privacy": ["zh": "隐私伪装", "en": "Privacy Camouflage"],
        "ios.sec.general": ["zh": "通用", "en": "General"],
        "ios.sec.network": ["zh": "网络", "en": "Network"],
        "ios.sec.advanced": ["zh": "高级", "en": "Advanced"],
        "ios.sec.icon": ["zh": "App 图标", "en": "App Icon"],
        "ios.sec.connection": ["zh": "连接", "en": "Connection"],
        "ios.sec.speed": ["zh": "测速", "en": "Speed Test"],
        "ios.sec.proxyMode": ["zh": "代理模式", "en": "Proxy Mode"],
        "ios.sec.dns": ["zh": "DNS", "en": "DNS"],
        "ios.sec.routing": ["zh": "分流", "en": "Routing"],
        "ios.sec.controls": ["zh": "快捷控制", "en": "Controls"],
        "ios.sec.diagnostics": ["zh": "诊断", "en": "Diagnostics"],
        "ios.sec.about": ["zh": "关于", "en": "About"],
        "ios.sec.language": ["zh": "语言 / Language", "en": "Language"],

        "ios.disguise.toggle": ["zh": "启动伪装锁屏", "en": "Camouflage lock screen"],
        "ios.disguise.hint": [
            "zh": "打开 App 先进入「水果保卫战」。切到后台会重新锁定。",
            "en": "App opens into Fruit Defense first. Backgrounding locks it again.",
        ],
        "ios.disguise.lockNow": ["zh": "立即锁定", "en": "Lock now"],
        "ios.icon.hint": [
            "zh": "专为手机主屏幕优化的 8 款图标。切换后桌面图标会立即更换；若仍是空白，请删掉 App 重装一次。",
            "en": "8 home-screen icons. Changes apply immediately; if blank, delete and reinstall the app.",
        ],
        "ios.icon.unsupported": ["zh": "当前系统不支持更换图标", "en": "Alternate icons not supported on this system"],

        "ios.conn.status": ["zh": "连接", "en": "Status"],
        "ios.conn.duration": ["zh": "时长", "en": "Duration"],
        "ios.conn.down": ["zh": "下行累计", "en": "Downloaded"],
        "ios.conn.up": ["zh": "上行累计", "en": "Uploaded"],
        "ios.conn.node": ["zh": "节点", "en": "Node"],
        "ios.conn.ip": ["zh": "出站 IP", "en": "Outbound IP"],
        "ios.conn.reconnect": ["zh": "重新连接 VPN", "en": "Reconnect VPN"],
        "ios.conn.disconnect": ["zh": "断开 VPN", "en": "Disconnect VPN"],

        "ios.speed.timeout": ["zh": "超时", "en": "Timeout"],
        "ios.speed.concurrency": ["zh": "并发", "en": "Concurrency"],

        "ios.proxy.picker": ["zh": "iOS 代理模式", "en": "iOS proxy mode"],
        "ios.proxy.tun": ["zh": "TUN 全量（推荐）", "en": "Full TUN (recommended)"],
        "ios.proxy.http": ["zh": "HTTP 代理（实验）", "en": "HTTP proxy (experimental)"],
        "ios.proxy.tun.hint": [
            "zh": "捕获全部 App 流量（微信、Telegram、Safari 等）。",
            "en": "Captures all app traffic (WeChat, Telegram, Safari, etc.).",
        ],
        "ios.proxy.http.hint": [
            "zh": "仅 Safari / 系统浏览器等支持 HTTP 代理的 App；微信、Telegram 不会走代理。",
            "en": "Only apps that honor HTTP proxy (Safari, etc.). WeChat/Telegram will not use it.",
        ],
        "ios.proxy.footer": [
            "zh": "切换后请断开再连接 VPN。HTTP 代理模式走本机 127.0.0.1:%@，不接管全量路由。",
            "en": "Reconnect VPN after switching. HTTP mode uses 127.0.0.1:%@ and does not take full routes.",
        ],
        "ios.dns.footer": ["zh": "修改 DNS 后请重新连接 VPN。", "en": "Reconnect VPN after changing DNS."],

        "ios.routing.version": ["zh": "规则版本", "en": "Rules version"],
        "ios.routing.count": ["zh": "生效条数", "en": "Active rules"],
        "ios.routing.adblock": ["zh": "去广告", "en": "Ad Block"],
        "ios.routing.restore": ["zh": "恢复智能规则 v%@", "en": "Restore smart rules v%@"],
        "ios.routing.footer": [
            "zh": "去广告默认开启：视频站广告域、开屏 SDK、电商跳转广告域。规则模式：国内直连，谷歌/Telegram 等走代理。",
            "en": "Ad Block is on by default (video ads, splash SDKs, ecommerce redirects). Rule mode: domestic direct; Google/Telegram via proxy.",
        ],

        "ios.controls.title": ["zh": "控制中心快捷开关", "en": "Control Center toggle"],
        "ios.controls.body": [
            "zh": "下拉控制中心 → 左上角「编辑」→ 添加「BashX VPN」，即可一键连接/断开。也可在「快捷指令」里搜索 BashX。",
            "en": "Control Center → Edit → add “BashX VPN” for one-tap connect/disconnect. Or search BashX in Shortcuts.",
        ],

        "ios.diag.core": ["zh": "Mihomo 内核", "en": "Mihomo core"],
        "ios.diag.core.ok": ["zh": "已加载 %@", "en": "Loaded %@"],
        "ios.diag.core.missing": ["zh": "未编译", "en": "Not built"],
        "ios.diag.config": ["zh": "配置文件", "en": "Config"],
        "ios.diag.config.ok": ["zh": "正常", "en": "OK"],
        "ios.diag.config.missing": ["zh": "缺失", "en": "Missing"],
        "ios.diag.log": ["zh": "查看隧道日志", "en": "View tunnel log"],
        "ios.diag.log.empty": ["zh": "（无日志）", "en": "(no log)"],
        "ios.about.version": ["zh": "版本", "en": "Version"],
        "ios.about.footer": ["zh": "BashX for iOS · Network Extension + Mihomo", "en": "BashX for iOS · Network Extension + Mihomo"],
        "ios.about.footerShort": [
            "zh": "控制中心可添加 BashX VPN 快捷开关",
            "en": "Add BashX VPN toggle in Control Center settings",
        ],

        // iOS Home
        "home.addSubFirst": ["zh": "请先添加订阅", "en": "Add a subscription first"],
        "home.pickNode": ["zh": "请选择节点", "en": "Select a node"],
        "home.selectNode": ["zh": "选择节点", "en": "Select node"],
        "home.hero.connected": ["zh": "已加密连接 · 流量受保护", "en": "Encrypted · traffic protected"],
        "home.hero.connecting": ["zh": "正在建立安全隧道…", "en": "Establishing secure tunnel…"],
        "home.hero.empty": ["zh": "添加订阅后即可一键连接", "en": "Add a subscription to connect"],
        "home.hero.ready": ["zh": "一键连接 · 智能分流保护隐私", "en": "One-tap connect · smart routing"],
        "home.mode.a11y": ["zh": "分流模式，当前%@", "en": "Routing mode, %@"],
        "home.firstUse": ["zh": "首次使用", "en": "Getting started"],
        "home.guide.1": ["zh": "添加订阅链接", "en": "Add a subscription URL"],
        "home.guide.2": ["zh": "更新并选择节点", "en": "Update and pick a node"],
        "home.guide.3": ["zh": "点连接，允许 VPN 权限", "en": "Connect and allow VPN"],
        "home.goAddSub": ["zh": "去添加订阅", "en": "Add subscription"],
        "home.location": ["zh": "连接位置", "en": "Location"],
        "home.nodesAvailable": ["zh": "%@ 个节点可用", "en": "%@ nodes available"],
        "home.loadingGroups": ["zh": "加载策略组…", "en": "Loading groups…"],
        "home.refresh": ["zh": "刷新", "en": "Refresh"],
        "home.groups": ["zh": "策略组", "en": "Proxy groups"],
        "home.refreshGroups": ["zh": "刷新策略组", "en": "Refresh groups"],
        "home.groupsMore": ["zh": "…共 %@ 个", "en": "…%@ total"],
        "home.quick": ["zh": "快捷控制", "en": "Quick actions"],
        "home.test": ["zh": "测速", "en": "Test"],
        "home.fastest": ["zh": "最快", "en": "Fastest"],
        "home.nodes": ["zh": "节点", "en": "Nodes"],
        "home.pickLocation": ["zh": "选择位置", "en": "Choose location"],
        "home.modeTitle": ["zh": "分流模式", "en": "Routing mode"],
        "home.modeHint": ["zh": "选择流量怎么走代理", "en": "How traffic should use the proxy"],
        "home.updateSubs": ["zh": "更新订阅", "en": "Update subscriptions"],

        // iOS Nodes
        "nodes.empty.title": ["zh": "暂无节点", "en": "No nodes"],
        "nodes.empty.msg": [
            "zh": "在「订阅」页添加链接并更新，节点会按地区显示在这里。",
            "en": "Add a subscription and update it. Nodes appear here by region.",
        ],
        "nodes.noMatch": ["zh": "没有匹配的节点", "en": "No matching nodes"],
        "nodes.search": ["zh": "搜索节点", "en": "Search nodes"],
        "nodes.title": ["zh": "节点", "en": "Nodes"],
        "nodes.sortDelay": ["zh": "按延迟", "en": "By latency"],
        "nodes.sortName": ["zh": "按名称", "en": "By name"],
        "nodes.testAll": ["zh": "测速全部", "en": "Test all"],
        "nodes.testFastest": ["zh": "测速并选最快", "en": "Test & pick fastest"],
        "nodes.syncVpn": ["zh": "同步到 VPN", "en": "Sync to VPN"],
        "nodes.all": ["zh": "全部", "en": "All"],
        "nodes.copyName": ["zh": "复制名称", "en": "Copy name"],
        "nodes.setCurrent": ["zh": "设为当前节点", "en": "Set as current"],

        // iOS Subscriptions
        "subs.title": ["zh": "订阅", "en": "Subscriptions"],
        "subs.empty.title": ["zh": "添加订阅", "en": "Add subscription"],
        "subs.empty.msg": [
            "zh": "粘贴 Clash 或机场订阅链接，更新后即可获取节点。",
            "en": "Paste a Clash or provider URL, then update to fetch nodes.",
        ],
        "subs.add": ["zh": "添加订阅", "en": "Add"],
        "subs.nodes": ["zh": "节点", "en": "Nodes"],
        "subs.updateAll": ["zh": "全部更新", "en": "Update all"],
        "subs.unnamed": ["zh": "未命名订阅", "en": "Untitled"],
        "subs.never": ["zh": "尚未更新", "en": "Not updated yet"],
        "subs.enabled": ["zh": "启用", "en": "Enabled"],
        "subs.updating": ["zh": "更新中…", "en": "Updating…"],
        "subs.updateOne": ["zh": "更新此订阅", "en": "Update this"],
        "subs.copyLink": ["zh": "复制链接", "en": "Copy link"],
        "subs.qrShare": ["zh": "二维码分享", "en": "Share QR"],
        "subs.shareLink": ["zh": "分享链接", "en": "Share link"],
        "subs.nameOptional": ["zh": "名称（可选）", "en": "Name (optional)"],
        "subs.url": ["zh": "订阅 URL", "en": "Subscription URL"],
        "subs.formHint": [
            "zh": "支持 Clash YAML 与 Base64 节点列表。",
            "en": "Supports Clash YAML and Base64 node lists.",
        ],
        "subs.paste": ["zh": "从剪贴板粘贴", "en": "Paste from clipboard"],
        "subs.scan": ["zh": "扫码添加", "en": "Scan QR code"],
        "subs.addManual": ["zh": "手动输入链接", "en": "Enter URL manually"],
        "subs.scan.title": ["zh": "扫描订阅二维码", "en": "Scan subscription QR"],
        "subs.scan.hint": [
            "zh": "将订阅二维码放入取景框，识别后会自动填入链接",
            "en": "Align the subscription QR code; the URL fills in automatically",
        ],
        "subs.scan.noCamera.title": ["zh": "无法使用相机", "en": "Camera unavailable"],
        "subs.scan.noCamera.msg": [
            "zh": "请在「设置 → BashX → 相机」中允许访问，或改用手动输入链接。",
            "en": "Allow camera access in Settings → BashX → Camera, or enter the URL manually.",
        ],
        "subs.scan.unavailable.title": ["zh": "扫码不可用", "en": "Scanning unavailable"],
        "subs.scan.unavailable.msg": [
            "zh": "当前设备不支持二维码扫描，请改用手动输入或粘贴链接。",
            "en": "QR scanning isn’t supported on this device. Paste or type the URL instead.",
        ],
        "subs.addTitle": ["zh": "添加订阅", "en": "Add subscription"],

        // Traffic chart
        "traffic.title": ["zh": "实时流量", "en": "Live traffic"],
        "traffic.connected": ["zh": "已连接 %@ · 峰 %@/s", "en": "Connected %@ · peak %@/s"],
        "traffic.needVpn": ["zh": "连接 VPN 后显示", "en": "Connect VPN to show"],
        "traffic.wait": ["zh": "等待流量…", "en": "Waiting for traffic…"],
        "traffic.none": ["zh": "暂无数据", "en": "No data"],
        "traffic.down": ["zh": "下行", "en": "Down"],
        "traffic.up": ["zh": "上行", "en": "Up"],

        // Connect control
        "connect.protected": ["zh": "已保护", "en": "Protected"],
        "connect.connecting": ["zh": "连接中", "en": "Connecting"],
        "connect.connect": ["zh": "连接", "en": "Connect"],
        "connect.a11y.disconnect": ["zh": "断开 VPN", "en": "Disconnect VPN"],
        "connect.a11y.connect": ["zh": "连接 VPN", "en": "Connect VPN"],

        // Website probe
        "probe.title": ["zh": "网站连通", "en": "Sites"],
        "probe.test": ["zh": "测试", "en": "Test"],
        "probe.testing": ["zh": "测试中", "en": "Testing"],
        "probe.fail": ["zh": "失败", "en": "Fail"],
        "probe.timeout": ["zh": "超时", "en": "Timeout"],
        "probe.noResult": ["zh": "无结果", "en": "No result"],
        "probe.noNetwork": ["zh": "无网络", "en": "Offline"],
        "probe.dnsFail": ["zh": "DNS 失败", "en": "DNS failed"],
        "probe.tlsFail": ["zh": "TLS 失败", "en": "TLS failed"],
        "probe.noResponse": ["zh": "无响应", "en": "No response"],
        "probe.parseFail": ["zh": "解析失败", "en": "Parse error"],
        "probe.badURL": ["zh": "无效 URL", "en": "Invalid URL"],
        "probe.baidu": ["zh": "百度", "en": "Baidu"],

        // QR share
        "qr.title": ["zh": "二维码分享", "en": "Share QR"],
        "qr.defaultName": ["zh": "订阅二维码", "en": "Subscription QR"],
        "qr.fail": ["zh": "无法生成二维码", "en": "Couldn’t create QR"],
        "qr.hint": [
            "zh": "对方用相机或 Clash / BashX 扫码即可获取订阅链接并添加",
            "en": "Scan with Camera, Clash, or BashX to add the subscription",
        ],
        "qr.share": ["zh": "分享", "en": "Share"],
        "qr.copyImage": ["zh": "复制二维码", "en": "Copy QR"],

        // Status / toast
        "status.ready": ["zh": "就绪", "en": "Ready"],
        "status.modeSwitched": ["zh": "已切换为%@模式%@", "en": "Switched to %@ mode%@"],
        "status.adOffNote": ["zh": "（去广告已关闭）", "en": " (ad block off)"],
        "status.adOn": ["zh": "去广告已开启（%@ 条）", "en": "Ad block on (%@ rules)"],
        "status.adOff": ["zh": "去广告已关闭", "en": "Ad block off"],
        "status.badURL": [
            "zh": "链接无效，请使用 http:// 或 https:// 开头",
            "en": "Invalid URL — use http:// or https://",
        ],
        "status.subDefault": ["zh": "订阅", "en": "Subscription"],
        "status.updatingSubs": ["zh": "更新订阅…", "en": "Updating subscriptions…"],
        "status.subsUpdated": ["zh": "订阅已更新 · %@ 节点", "en": "Subscriptions updated · %@ nodes"],
        "status.subsAllFail": ["zh": "全部更新失败（%@ 个）", "en": "All updates failed (%@)"],
        "status.subsPartial": [
            "zh": "部分成功：%@ 成功，%@ 失败 · %@ 节点",
            "en": "Partial: %@ ok, %@ failed · %@ nodes",
        ],
        "status.updatingOne": ["zh": "更新 %@…", "en": "Updating %@…"],
        "status.oneBadURL": ["zh": "「%@」链接无效", "en": "“%@” URL invalid"],
        "status.oneUpdated": ["zh": "已更新「%@」· %@ 节点", "en": "Updated “%@” · %@ nodes"],
        "status.oneFail": ["zh": "「%@」更新失败：%@", "en": "“%@” update failed: %@"],
        "status.disconnectRetry": ["zh": "（可先断开 VPN 再试）", "en": " (try disconnecting VPN first)"],
        "status.icon": ["zh": "图标：%@", "en": "Icon: %@"],
        "status.selected": ["zh": "已选：%@", "en": "Selected: %@"],
        "status.needVpnSwitch": ["zh": "请先连接 VPN 再切换 %@", "en": "Connect VPN before switching %@"],
        "status.switching": ["zh": "切换 %@ → %@", "en": "Switching %@ → %@"],
        "status.groupSelected": ["zh": "%@ 已选：%@", "en": "%@ selected: %@"],
        "status.ipFail": ["zh": "查询失败", "en": "Lookup failed"],
        "status.rulesApplied": [
            "zh": "已应用 BashX 智能规则 v%@（%@ 条）",
            "en": "Applied BashX smart rules v%@ (%@ rules)",
        ],
        "status.dnsReconnect": [
            "zh": "DNS 已设为%@，请重连 VPN 生效",
            "en": "DNS set to %@ — reconnect VPN",
        ],
        "status.dnsSet": ["zh": "DNS 已设为%@", "en": "DNS set to %@"],
        "status.tunOn": ["zh": "已切换为 TUN 模式，请重连 VPN", "en": "Switched to TUN — reconnect VPN"],
        "status.tunOff": [
            "zh": "已切换为 HTTP 代理模式，请重连 VPN",
            "en": "Switched to HTTP proxy — reconnect VPN",
        ],
        "status.testing": ["zh": "测速中…", "en": "Testing…"],
        "status.tested": ["zh": "测速完成", "en": "Speed test done"],
        "status.needSubs": [
            "zh": "请先添加订阅并更新节点",
            "en": "Add a subscription and update nodes first",
        ],

        // VPN status
        "vpn.disconnected": ["zh": "未连接", "en": "Disconnected"],
        "vpn.connecting": ["zh": "连接中…", "en": "Connecting…"],
        "vpn.connected": ["zh": "已连接", "en": "Connected"],
        "vpn.reconnecting": ["zh": "重连中…", "en": "Reconnecting…"],
        "vpn.disconnecting": ["zh": "断开中…", "en": "Disconnecting…"],
        "vpn.unknown": ["zh": "未知", "en": "Unknown"],
        "vpn.otherVpn": [
            "zh": "检测到其他 VPN 仍在运行。已尝试关闭系统 VPN；请到「设置 → VPN」关掉第三方 VPN 后再连 BashX。",
            "en": "Another VPN is running. Tried closing system VPN; turn off third-party VPNs in Settings → VPN, then retry.",
        ],
        "vpn.fail": ["zh": "VPN 连接失败", "en": "VPN connection failed"],
        "vpn.timeout": [
            "zh": "连接超时，请检查网络后重试",
            "en": "Connection timed out — check network and retry",
        ],

        // Mac settings tabs
        "mac.tab.general": ["zh": "常用", "en": "General"],
        "mac.tab.speed": ["zh": "测速", "en": "Speed"],
        "mac.tab.proxy": ["zh": "外置代理", "en": "Proxy"],
        "mac.tab.core": ["zh": "内核", "en": "Core"],
        "mac.tab.appearance": ["zh": "外观", "en": "Look"],
        "mac.tab.about": ["zh": "关于", "en": "About"],
        "mac.appearance.section": ["zh": "外观", "en": "Appearance"],
        "mac.appearance.theme": ["zh": "界面主题", "en": "Theme"],
        "mac.adblock": ["zh": "去广告", "en": "Ad Block"],
        "mac.adblock.hint": [
            "zh": "默认开启。拦截国内外视频广告域、App 开屏/插屏广告 SDK、京东/天猫等电商联盟跳转域。需「规则」模式；与正片同 CDN 的贴片无法域名拦截。",
            "en": "On by default. Blocks video ad hosts, splash SDKs, and ecommerce redirect domains. Needs Rule mode; same-CDN mid-roll ads cannot be blocked by domain.",
        ],

        // Mac menu bar
        "mac.menu.openPanel": ["zh": "打开面板", "en": "Open Panel"],
        "mac.menu.proxyMode": ["zh": "代理模式：%@", "en": "Mode: %@"],
        "mac.menu.systemProxy": ["zh": "系统代理", "en": "System Proxy"],
        "mac.menu.closeOnSwitch": ["zh": "切节点关闭连接", "en": "Close on Switch"],
        "mac.menu.launchAtLogin": ["zh": "开机自动启动", "en": "Launch at Login"],
        "mac.menu.showTraffic": ["zh": "显示网速", "en": "Show Speeds"],
        "mac.menu.tun": ["zh": "TUN 模式", "en": "TUN Mode"],
        "mac.menu.adblock": ["zh": "去广告", "en": "Ad Block"],
        "mac.menu.speedTest": ["zh": "一键测速", "en": "Speed Test"],
        "mac.menu.speedTesting": ["zh": "测速中…", "en": "Testing…"],
        "mac.menu.copyEnv": ["zh": "复制终端代理环境变量", "en": "Copy Proxy Env Vars"],
        "mac.menu.quit": ["zh": "退出 BashX", "en": "Quit BashX"],
        "mac.menu.noNodes": ["zh": "暂无节点", "en": "No nodes"],
        "mac.menu.nodes": ["zh": "节点%1 · 最快%2", "en": "Nodes%1 · top %2"],
        "mac.menu.allNodes": ["zh": "全部节点…", "en": "All nodes…"],
        "mac.menu.subs": ["zh": "订阅", "en": "Subscriptions"],
        "mac.menu.subsNone": ["zh": "暂无订阅", "en": "No subscriptions"],
        "mac.menu.subsDisabled": ["zh": "订阅 · 未启用", "en": "Subs · none enabled"],
        "mac.menu.subsEnabled": ["zh": "订阅 · %@ 个启用", "en": "Subs · %@ enabled"],
        "mac.menu.addSub": ["zh": "添加订阅…", "en": "Add subscription…"],
        "mac.menu.pasteSub": ["zh": "从剪贴板添加", "en": "Paste from clipboard"],
        "mac.menu.updateAll": ["zh": "更新全部", "en": "Update all"],
        "mac.menu.updating": ["zh": "更新中…", "en": "Updating…"],
        "mac.menu.manageSubs": ["zh": "管理订阅…", "en": "Manage subscriptions…"],
        "mac.menu.settings": ["zh": "设置", "en": "Settings"],
        "mac.menu.autoSpeed": ["zh": "自动测速", "en": "Auto Speed Test"],
        "mac.menu.autoFastest": ["zh": "跟最快节点", "en": "Follow Fastest"],
        "mac.menu.logo": ["zh": "Logo：%@", "en": "Logo: %@"],
        "mac.menu.openConfig": ["zh": "打开配置目录", "en": "Open Config Folder"],
        "mac.menu.moreSettings": ["zh": "更多设置…", "en": "More Settings…"],
        "mac.menu.coreRunning": ["zh": "内核运行中", "en": "Core running"],
        "mac.menu.coreStopped": ["zh": "内核未启动", "en": "Core stopped"],
        "mac.menu.groupMore": ["zh": "…共 %@ 个", "en": "…%@ total"],
        "mac.menu.pasteNoUrl": [
            "zh": "剪贴板没有订阅链接，已打开面板添加",
            "en": "No subscription URL in clipboard — opened panel to add",
        ],

        // Mac panel
        "mac.panel.nodes": ["zh": "节点", "en": "Nodes"],
        "mac.nodes.smart": ["zh": "智能", "en": "Smart"],
        "mac.nodes.smartNeedNodes": ["zh": "需先有节点", "en": "Add nodes first"],
        "mac.nodes.autoSpeed": ["zh": "自动测速", "en": "Auto test"],
        "mac.nodes.autoSpeed.sub": ["zh": "更新订阅后自动测速", "en": "Test after sub update"],
        "mac.nodes.autoFastest": ["zh": "跟最快", "en": "Fastest"],
        "mac.nodes.autoFastest.sub": ["zh": "自动切到延迟最低", "en": "Switch to lowest latency"],
        "mac.nodes.adblock": ["zh": "去广告", "en": "Ad block"],
        "mac.nodes.adblock.sub": ["zh": "视频/电商跳转拦截", "en": "Block video & ad redirects"],
        "mac.panel.apps": ["zh": "应用", "en": "Apps"],
        "mac.panel.subscriptions": ["zh": "订阅", "en": "Subs"],
        "mac.panel.monitor": ["zh": "监控", "en": "Monitor"],
        "mac.panel.rules": ["zh": "规则", "en": "Rules"],

        "mac.currentNode.title": ["zh": "当前节点", "en": "Current node"],
        "mac.currentNode.auto": ["zh": "未选择（AUTO）", "en": "Not selected (AUTO)"],
        "mac.currentNode.selected": ["zh": "选用：%@", "en": "Selected: %@"],

        "mac.apps.title": ["zh": "应用分组", "en": "App routing"],
        "mac.apps.subtitle": [
            "zh": "按应用指定线路（需 TUN 或系统代理 + 进程匹配）",
            "en": "Route apps via PROCESS-NAME rules (TUN or system proxy + process match)",
        ],
        "mac.apps.add": ["zh": "添加应用", "en": "Add app"],
        "mac.apps.empty": ["zh": "还没有应用分组", "en": "No app routes yet"],
        "mac.apps.emptyHint": [
            "zh": "例如让 Chrome 走美国节点、Telegram 走香港节点。",
            "en": "e.g. Chrome via US node, Telegram via HK node.",
        ],
        "mac.apps.pick": ["zh": "选择运行中的应用", "en": "Pick a running app"],
        "mac.apps.routeTo": ["zh": "走线路", "en": "Route via"],
        "mac.apps.search": ["zh": "搜索应用", "en": "Search apps"],
        "mac.apps.added": ["zh": "已添加", "en": "Added"],
        "mac.apps.presets": ["zh": "常用应用", "en": "Common apps"],
        "mac.apps.presetsHint": ["zh": "点击添加，已添加显示 ✓", "en": "Tap to add · ✓ = added"],
        "mac.apps.addAll": ["zh": "添加全部", "en": "Add all"],
        "mac.apps.addPreset": ["zh": "添加 %@", "en": "Add %@"],
        "mac.apps.custom": ["zh": "已配置", "en": "Configured"],
        "mac.apps.cat.im": ["zh": "即时通讯", "en": "Messaging"],
        "mac.apps.cat.browser": ["zh": "浏览器", "en": "Browsers"],
        "mac.apps.cat.domestic": ["zh": "国内应用", "en": "Domestic"],
        "mac.apps.cat.streaming": ["zh": "流媒体 / 会议", "en": "Streaming"],
        "mac.apps.cat.dev": ["zh": "开发工具", "en": "Developer"],
        "mac.apps.probeHint": ["zh": "验证各线路可达性", "en": "Check route reachability"],

        // Mac monitor
        "mac.monitor.traffic": ["zh": "流量", "en": "Traffic"],
        "mac.monitor.peak": ["zh": "峰 %1 / %2", "en": "Peak %1 / %2"],
        "mac.monitor.live": ["zh": "实时", "en": "Live"],
        "mac.monitor.offline": ["zh": "离线", "en": "Offline"],
        "mac.monitor.down": ["zh": "下载", "en": "Download"],
        "mac.monitor.up": ["zh": "上传", "en": "Upload"],
        "mac.monitor.connections": ["zh": "连接", "en": "Connections"],
        "mac.monitor.logs": ["zh": "日志", "en": "Logs"],
        "mac.monitor.count": ["zh": "%@ 条", "en": "%@ items"],
        "mac.monitor.clearConn": ["zh": "清空连接", "en": "Clear all"],
        "mac.monitor.clearLogs": ["zh": "清空日志", "en": "Clear logs"],
        "mac.monitor.coreOff": ["zh": "内核未运行", "en": "Core offline"],
        "mac.monitor.coreOffHint": ["zh": "启动内核后可查看连接", "en": "Start the core to view connections"],
        "mac.monitor.noConn": ["zh": "暂无活跃连接", "en": "No active connections"],
        "mac.monitor.noConnHint": ["zh": "产生流量后会显示在这里", "en": "Connections appear when traffic flows"],
        "mac.monitor.closeConn": ["zh": "关闭此连接", "en": "Close connection"],
        "mac.monitor.logsOffHint": ["zh": "启动内核后可查看日志", "en": "Start the core to view logs"],
        "mac.monitor.waitLogs": ["zh": "等待日志…", "en": "Waiting for logs…"],
        "mac.monitor.waitLogsHint": ["zh": "有请求时会实时滚动显示", "en": "Logs stream in as requests happen"],

        // Mac settings — general
        "mac.sec.proxyMode": ["zh": "代理模式", "en": "Proxy mode"],
        "mac.sec.systemProxy": ["zh": "系统代理", "en": "System proxy"],
        "mac.systemProxy.hint": [
            "zh": "开启前会备份原有代理；关闭时自动恢复。指向 127.0.0.1:%@。",
            "en": "Backs up existing proxy before enable; restores on disable. Points to 127.0.0.1:%@.",
        ],
        "mac.restoreProxy": ["zh": "恢复网络代理备份", "en": "Restore proxy backup"],
        "mac.closeConnOnSwitch": ["zh": "切节点时关闭连接", "en": "Close connections on switch"],
        "mac.closeConnOnSwitch.hint": [
            "zh": "切换节点后断开旧连接，避免流量仍走旧节点。",
            "en": "Drop old connections after switching nodes.",
        ],
        "mac.tun": ["zh": "TUN 模式", "en": "TUN mode"],
        "mac.tun.hint": [
            "zh": "增强模式，可接管更多流量。首次会安装 TUN 权限（输一次管理员密码），之后开关无需再输。",
            "en": "Enhanced mode captures more traffic. First enable installs TUN helper (one admin password).",
        ],
        "mac.httpSubs": ["zh": "允许不安全 HTTP 订阅", "en": "Allow insecure HTTP subscriptions"],
        "mac.httpSubs.hint": [
            "zh": "默认仅 HTTPS。开启后才接受 http:// 订阅链接。",
            "en": "HTTPS only by default. Enable to allow http:// subscription URLs.",
        ],
        "mac.sec.dns": ["zh": "DNS 优选", "en": "DNS"],
        "mac.dns.picker": ["zh": "解析策略", "en": "Resolver"],
        "mac.dns.reloadHint": [
            "zh": "修改后自动写入 config.yaml 并重载内核。",
            "en": "Changes are written to config.yaml and reload the core.",
        ],
        "mac.sec.shortcuts": ["zh": "快捷入口", "en": "Shortcuts"],
        "mac.openConfig": ["zh": "打开配置目录", "en": "Open config folder"],
        "mac.openConfig.hint": [
            "zh": "config.yaml、订阅缓存与规则文件。",
            "en": "config.yaml, subscription cache, and rule files.",
        ],
        "mac.openDashboard": ["zh": "打开 Dashboard", "en": "Open Dashboard"],
        "mac.openDashboard.hint": [
            "zh": "Clash 控制面板 · 连接 / 规则可视化（需内核运行）。",
            "en": "Clash dashboard — connections and rules (core must be running).",
        ],
        "mac.sec.launch": ["zh": "启动", "en": "Launch"],
        "mac.launchAtLogin": ["zh": "开机自动启动", "en": "Launch at login"],
        "mac.launchAtLogin.sub": ["zh": "登录后自动运行", "en": "Run when you log in"],
        "mac.launchAtLogin.hint": [
            "zh": "开启后登录 Mac 会自动运行 BashX（菜单栏）。若提示需批准，请到「系统设置 → 通用 → 登录项」。",
            "en": "Runs BashX in the menu bar at login. Approve in System Settings → General → Login Items if prompted.",
        ],
        "mac.sec.speedQuick": ["zh": "测速快捷", "en": "Speed test"],
        "mac.autoSpeed": ["zh": "自动测速", "en": "Auto speed test"],
        "mac.autoFastest": ["zh": "测速后自动选用最快节点", "en": "Auto-select fastest after test"],
        "mac.speedQuick.hint": [
            "zh": "更细的超时 / 并发 / 间隔请到「测速」页。",
            "en": "Timeout, concurrency, and interval are on the Speed tab.",
        ],
        "mac.nodeDisplay": ["zh": "节点展示", "en": "Node layout"],
        "mac.menuNodeLimit": ["zh": "菜单栏节点数：%@", "en": "Menu bar nodes: %@"],
        "mac.menuNode.hint": [
            "zh": "菜单栏展示延迟最快的前 %@ 个节点；面板内仍显示全部。",
            "en": "Menu bar shows the %@ fastest nodes; panel shows all.",
        ],
        "mac.hotkeys.hint": [
            "zh": "全局快捷键：⌃⌘P 切换系统代理 · ⌃⌘M 循环 规则/全局/直连",
            "en": "Hotkeys: ⌃⌘P toggle system proxy · ⌃⌘M cycle Rule/Global/Direct",
        ],
        "mac.menuTraffic": ["zh": "菜单栏显示网速", "en": "Show speeds in menu bar"],
        "mac.menuTraffic.hint": [
            "zh": "在 Logo 旁显示 ↓/↑。若菜单栏图标「消失」，多半被挤进右侧 ❯❯，关掉此项或点 ❯❯ 查看；也可开「程序坞显示图标」。",
            "en": "Shows ↓/↑ beside the logo. If the icon vanishes into ❯❯, disable this or enable the Dock icon.",
        ],
        "mac.dockIcon": ["zh": "程序坞显示图标", "en": "Show Dock icon"],
        "mac.dockIcon.hint": [
            "zh": "关闭后仅保留菜单栏图标；开启后 BashX 会常驻程序坞。",
            "en": "Menu bar only when off; stays in the Dock when on.",
        ],
        "mac.sec.speed": ["zh": "参数", "en": "Parameters"],
        "mac.timeout": ["zh": "超时 (ms)", "en": "Timeout (ms)"],
        "mac.concurrency": ["zh": "并发数", "en": "Concurrency"],
        "mac.testURL": ["zh": "测速 URL", "en": "Test URL"],
        "mac.sec.perf": ["zh": "性能", "en": "Performance"],
        "mac.turbo": ["zh": "极速模式", "en": "Turbo mode"],
        "mac.appearance.langTab": ["zh": "语言 / Language", "en": "Language"],
        "mac.appearance.footer": [
            "zh": "主题、展示方式切换后立即生效；Logo 同步到菜单栏。",
            "en": "Theme and layout apply instantly; logo syncs to the menu bar.",
        ],
        "mac.settings.title": ["zh": "BashX 设置", "en": "BashX Settings"],
        "mac.restoreProxy.ok": ["zh": "已恢复开启前的系统代理设置", "en": "Restored previous system proxy settings"],
        "mac.restoreProxy.none": ["zh": "没有可恢复的备份", "en": "No proxy backup to restore"],
        "mac.tun.install": ["zh": "安装 TUN 授权", "en": "Install TUN helper"],
        "mac.tun.reinstall": ["zh": "重新安装授权", "en": "Reinstall helper"],
        "mac.tun.remove": ["zh": "移除授权", "en": "Remove helper"],
        "mac.tun.ready": ["zh": "TUN 权限已就绪，之后开 TUN 无需密码", "en": "TUN helper ready — no password needed next time"],
        "mac.tun.removed": ["zh": "已移除 TUN 权限", "en": "TUN helper removed"],
        "mac.httpSubs.on": ["zh": "已允许明文 HTTP 订阅（不推荐）", "en": "HTTP subscriptions allowed (not recommended)"],
        "mac.httpSubs.off": ["zh": "仅允许 HTTPS 订阅", "en": "HTTPS subscriptions only"],
        "mac.turbo.hint": [
            "zh": "开启后启用 mihomo 多连接并发、懒测速，下载/多线程场景更快。",
            "en": "Enables mihomo multi-connection and lazy speed tests for faster downloads.",
        ],
        "mac.sniffing": ["zh": "域名嗅探", "en": "Domain sniffing"],
        "mac.sniffing.hint": [
            "zh": "帮助非浏览器应用正确分流；极少数软件可能不兼容。",
            "en": "Helps non-browser apps route correctly; rare incompatibilities possible.",
        ],
        "mac.sec.auto": ["zh": "自动", "en": "Automatic"],
        "mac.autoInterval": ["zh": "自动测速间隔（分钟）", "en": "Auto test interval (minutes)"],
        "mac.autoSpeed.detail": [
            "zh": "开启后按延迟把最快节点排到前面；自动测速会定时重测。",
            "en": "Sorts fastest nodes first; auto test reruns on the interval.",
        ],
        "mac.proxy.status": ["zh": "状态", "en": "Status"],
        "mac.proxy.core": ["zh": "内核", "en": "Core"],
        "mac.proxy.ports": ["zh": "端口", "en": "Ports"],
        "mac.proxy.address": ["zh": "地址", "en": "Address"],
        "mac.proxy.allowLan": ["zh": "允许局域网连接", "en": "Allow LAN connections"],
        "mac.proxy.lanHint": [
            "zh": "开启后 mixed-port 可被局域网访问；会自动确保 API secret，并把 external-controller 限制在 127.0.0.1。",
            "en": "LAN can reach mixed-port; ensures API secret and binds controller to 127.0.0.1.",
        ],
        "mac.proxy.portHint": [
            "zh": "HTTP 与 SOCKS5 共用 mixed-port。改端口后需重启内核。",
            "en": "HTTP and SOCKS5 share mixed-port. Restart core after changing port.",
        ],
        "mac.proxy.copy": ["zh": "复制", "en": "Copy"],
        "mac.proxy.example": ["zh": "示例", "en": "Examples"],
        "mac.copyHost": ["zh": "复制地址", "en": "Copy address"],
        "mac.copyHTTP": ["zh": "复制 HTTP", "en": "Copy HTTP"],
        "mac.copySOCKS": ["zh": "复制 SOCKS5", "en": "Copy SOCKS5"],
        "mac.copyEnv": ["zh": "复制环境变量", "en": "Copy env vars"],
        "mac.core.paths": ["zh": "路径与 API", "en": "Paths & API"],
        "mac.core.binary": ["zh": "mihomo/clash 路径", "en": "mihomo/clash path"],
        "mac.core.defaultPorts": [
            "zh": "默认使用 17890/19090，避免和 Stash/ClashX 的 7890/9090 冲突。",
            "en": "Defaults to 17890/19090 to avoid Stash/ClashX 7890/9090 conflicts.",
        ],
        "mac.core.stack": ["zh": "协议栈", "en": "Stack"],
        "mac.core.tunHint": [
            "zh": "开启 TUN 时启动内核会请求一次管理员权限；退出软件不再要求密码。",
            "en": "Enabling TUN may ask for admin once at core start; not on quit.",
        ],
        "mac.core.maint": ["zh": "维护", "en": "Maintenance"],
        "mac.core.dashHint": [
            "zh": "连接 / 日志 / 规则可视化；优先打开本机 mihomo /ui，否则使用 metacubexd。",
            "en": "Connections, logs, rules UI — local mihomo /ui first, else metacubexd.",
        ],
        "mac.core.bundled": [
            "zh": "mihomo 已内置在 App 中，启动时自动安装并运行，无需手动下载。",
            "en": "mihomo is bundled; installed and started automatically.",
        ],
        "mac.core.stop": ["zh": "停止内核", "en": "Stop core"],
        "mac.core.start": ["zh": "启动内核", "en": "Start core"],
        "mac.core.repair": ["zh": "修复内核", "en": "Repair core"],
        "mac.about.tagline": ["zh": "轻量菜单栏代理客户端", "en": "Lightweight menu bar proxy client"],
        "mac.about.subtitle": [
            "zh": "订阅管理 · 智能分流 · 系统代理 · 流量监控",
            "en": "Subscriptions · smart routing · system proxy · traffic monitor",
        ],
        "mac.about.f1": ["zh": "多订阅合并", "en": "Multi-subscription merge"],
        "mac.about.f1d": ["zh": "勾选多个订阅，节点自动合并到同一列表", "en": "Enable multiple subs; nodes merge into one list"],
        "mac.about.f2": ["zh": "系统代理 / TUN", "en": "System proxy / TUN"],
        "mac.about.f2d": ["zh": "一键接管系统流量，可选增强模式", "en": "One-click system traffic capture with optional TUN"],
        "mac.about.f3": ["zh": "规则 / 全局 / 直连", "en": "Rule / Global / Direct"],
        "mac.about.f3d": ["zh": "BashX 智能规则分流，支持去广告", "en": "BashX smart rules with ad blocking"],
        "mac.about.f4": ["zh": "测速与菜单栏", "en": "Speed test & menu bar"],
        "mac.about.f4d": ["zh": "延迟测速、最快节点、网速可开关展示", "en": "Latency tests, fastest node, optional menu bar speeds"],
        "mac.about.version": ["zh": "版本", "en": "Version"],
        "mac.about.rules": ["zh": "智能规则", "en": "Smart rules"],
        "mac.about.configDir": ["zh": "配置目录", "en": "Config folder"],
        "mac.about.footer": [
            "zh": "macOS 菜单栏代理工具 · 内核基于 mihomo / Clash Meta",
            "en": "macOS menu bar proxy · powered by mihomo / Clash Meta",
        ],
        "mac.update.title": ["zh": "软件更新", "en": "Software update"],
        "mac.update.lastCheck": ["zh": "上次检查 %@", "en": "Last checked %@"],
        "mac.update.download": ["zh": "下载并安装", "en": "Download & install"],
        "mac.update.openReleases": ["zh": "打开发布页", "en": "Open releases"],
        "mac.update.footer": [
            "zh": "检查到新版本后可直接下载安装，完成后请重启 BashX。",
            "en": "Download and install updates, then restart BashX.",
        ],
        "mac.update.idle": ["zh": "点击「检查更新」获取最新版本。", "en": "Tap Check for updates to fetch the latest release."],
        "mac.update.checking": ["zh": "正在检查更新…", "en": "Checking for updates…"],
        "mac.update.checkingBtn": ["zh": "检查中…", "en": "Checking…"],
        "mac.update.check": ["zh": "检查更新", "en": "Check for updates"],
        "mac.update.upToDate": ["zh": "已是最新版本（当前 %1，GitHub %2）", "en": "Up to date (%1, GitHub %2)"],
        "mac.update.ahead": ["zh": "当前 %1 高于 GitHub 最新 %2，无需更新", "en": "%1 is ahead of GitHub %2 — no update needed"],
        "mac.update.available": ["zh": "发现新版本 %1（当前 %2）", "en": "New version %1 (current %2)"],
        "mac.update.pkgSize": ["zh": "安装包 %@", "en": "Package %@"],
        "mac.update.downloading": ["zh": "正在下载… %@%", "en": "Downloading… %@%"],
        "mac.update.downloaded": [
            "zh": "下载完成，已打开安装包。请将 BashX 拖入「应用程序」后重启。",
            "en": "Download complete. Drag BashX to Applications, then restart.",
        ],
    ]
}
