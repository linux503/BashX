import Foundation

enum NodeCategory {
    struct Group: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let title: String
        let flag: String
        let nodes: [ProxyNode]
    }

    /// Composite regions shown as top-level groups.
    private static let gatCodes: Set<String> = ["HK", "MO", "TW"]
    private static let jkCodes: Set<String> = ["JP", "KR"]
    private static let anzCodes: Set<String> = ["AU", "NZ"]
    /// North America — US + Canada.
    private static let uscaCodes: Set<String> = ["US", "CA"]
    /// Europe (continent bucket).
    private static let euCodes: Set<String> = [
        "GB", "UK", "IE", "FR", "DE", "NL", "BE", "CH", "AT", "IT", "ES", "PT",
        "SE", "NO", "FI", "DK", "PL", "CZ", "HU", "RO", "UA", "GR", "IS", "LU",
        "AD", "MT", "MC", "LI", "SM", "VA", "CY", "BG", "HR", "SK", "SI", "EE", "LV", "LT",
    ]
    /// Africa (continent bucket).
    private static let afCodes: Set<String> = [
        "NG", "EG", "ZA", "KE", "MA", "TN", "DZ", "GH", "ET", "TZ", "UG", "SN", "CM", "CI",
    ]
    /// CIS / Central Asia.
    private static let cisCodes: Set<String> = [
        "RU", "KZ", "UZ", "GE", "AM", "AZ", "BY", "MD", "KG", "TJ", "TM",
    ]

    /// Southeast Asia — always shown as one region.
    private static let seaCodes: Set<String> = [
        "SG", "TH", "VN", "PH", "MY", "ID", "KH", "MM", "LA", "BN", "TL"
    ]

    /// South Asia (印度次大陆).
    private static let sasCodes: Set<String> = [
        "IN", "PK", "BD", "LK", "NP", "BT", "MV"
    ]

    /// South America.
    private static let samCodes: Set<String> = [
        "AR", "BR", "CL", "PE", "CO", "UY", "PY", "BO", "EC", "VE", "GY", "SR", "FK"
    ]

    /// Central America / Caribbean (墨西哥单独保留为大区时也并入拉美南翼外).
    private static let camCodes: Set<String> = [
        "PA", "CR", "CU", "GT", "HN", "NI", "SV", "DO", "JM", "TT"
    ]

    /// Middle East.
    private static let meCodes: Set<String> = [
        "AE", "SA", "IL", "TR", "QA", "KW", "BH", "OM", "JO", "IQ", "IR", "LB", "SY", "YE"
    ]

    /// Keep these as standalone even when only 1 node.
    private static let majorCodes: Set<String> = [
        "GAT", "JK", "ANZ", "SEA", "SAS", "SAM", "CAM", "ME",
        "USCA", "EU", "AF", "CIS",
        "HK", "MO", "TW", "JP", "KR", "US", "CA", "MX", "GB", "UK",
        "DE", "FR", "NL", "AU", "CN", "OTHER", "SPARSE",
    ]

    private static let codeTitles: [(code: String, title: String, flag: String)] = [
        ("GAT", "港澳台", "🇭🇰"),
        ("JK", "日韩", "🇯🇵"),
        ("ANZ", "澳新", "🇦🇺"),
        ("USCA", "美加", "🇺🇸"),
        ("EU", "欧洲", "🇪🇺"),
        ("AF", "非洲", "🌍"),
        ("CIS", "独联体", "🌐"),
        ("HK", "香港", "🇭🇰"),
        ("MO", "澳门", "🇲🇴"),
        ("TW", "台湾", "🇹🇼"),
        ("SG", "新加坡", "🇸🇬"),
        ("JP", "日本", "🇯🇵"),
        ("KR", "韩国", "🇰🇷"),
        ("US", "美国", "🇺🇸"),
        ("CA", "加拿大", "🇨🇦"),
        ("MX", "墨西哥", "🇲🇽"),
        ("GB", "英国", "🇬🇧"),
        ("UK", "英国", "🇬🇧"),
        ("IE", "爱尔兰", "🇮🇪"),
        ("FR", "法国", "🇫🇷"),
        ("DE", "德国", "🇩🇪"),
        ("NL", "荷兰", "🇳🇱"),
        ("BE", "比利时", "🇧🇪"),
        ("CH", "瑞士", "🇨🇭"),
        ("AT", "奥地利", "🇦🇹"),
        ("IT", "意大利", "🇮🇹"),
        ("ES", "西班牙", "🇪🇸"),
        ("PT", "葡萄牙", "🇵🇹"),
        ("SE", "瑞典", "🇸🇪"),
        ("NO", "挪威", "🇳🇴"),
        ("FI", "芬兰", "🇫🇮"),
        ("DK", "丹麦", "🇩🇰"),
        ("PL", "波兰", "🇵🇱"),
        ("CZ", "捷克", "🇨🇿"),
        ("HU", "匈牙利", "🇭🇺"),
        ("RO", "罗马尼亚", "🇷🇴"),
        ("UA", "乌克兰", "🇺🇦"),
        ("RU", "俄罗斯", "🇷🇺"),
        ("TR", "土耳其", "🇹🇷"),
        ("AE", "阿联酋", "🇦🇪"),
        ("SA", "沙特", "🇸🇦"),
        ("IL", "以色列", "🇮🇱"),
        ("IN", "印度", "🇮🇳"),
        ("PK", "巴基斯坦", "🇵🇰"),
        ("BD", "孟加拉", "🇧🇩"),
        ("LK", "斯里兰卡", "🇱🇰"),
        ("TH", "泰国", "🇹🇭"),
        ("VN", "越南", "🇻🇳"),
        ("PH", "菲律宾", "🇵🇭"),
        ("MY", "马来西亚", "🇲🇾"),
        ("ID", "印尼", "🇮🇩"),
        ("KH", "柬埔寨", "🇰🇭"),
        ("MM", "缅甸", "🇲🇲"),
        ("LA", "老挝", "🇱🇦"),
        ("BN", "文莱", "🇧🇳"),
        ("MV", "马尔代夫", "🇲🇻"),
        ("BT", "不丹", "🇧🇹"),
        ("NP", "尼泊尔", "🇳🇵"),
        ("MN", "蒙古", "🇲🇳"),
        ("KZ", "哈萨克", "🇰🇿"),
        ("UZ", "乌兹别克", "🇺🇿"),
        ("GE", "格鲁吉亚", "🇬🇪"),
        ("AM", "亚美尼亚", "🇦🇲"),
        ("AZ", "阿塞拜疆", "🇦🇿"),
        ("AU", "澳大利亚", "🇦🇺"),
        ("NZ", "新西兰", "🇳🇿"),
        ("FJ", "斐济", "🇫🇯"),
        ("PW", "帕劳", "🇵🇼"),
        ("AR", "阿根廷", "🇦🇷"),
        ("BR", "巴西", "🇧🇷"),
        ("CL", "智利", "🇨🇱"),
        ("PE", "秘鲁", "🇵🇪"),
        ("CO", "哥伦比亚", "🇨🇴"),
        ("UY", "乌拉圭", "🇺🇾"),
        ("PY", "巴拉圭", "🇵🇾"),
        ("BO", "玻利维亚", "🇧🇴"),
        ("EC", "厄瓜多尔", "🇪🇨"),
        ("VE", "委内瑞拉", "🇻🇪"),
        ("CU", "古巴", "🇨🇺"),
        ("PA", "巴拿马", "🇵🇦"),
        ("CR", "哥斯达黎加", "🇨🇷"),
        ("NG", "尼日利亚", "🇳🇬"),
        ("EG", "埃及", "🇪🇬"),
        ("ZA", "南非", "🇿🇦"),
        ("KE", "肯尼亚", "🇰🇪"),
        ("IO", "英属印度洋", "🇮🇴"),
        ("AD", "安道尔", "🇦🇩"),
        ("MT", "马耳他", "🇲🇹"),
        ("IS", "冰岛", "🇮🇸"),
        ("LU", "卢森堡", "🇱🇺"),
        ("MC", "摩纳哥", "🇲🇨"),
        ("LI", "列支敦士登", "🇱🇮"),
        ("SM", "圣马力诺", "🇸🇲"),
        ("VA", "梵蒂冈", "🇻🇦"),
        ("CY", "塞浦路斯", "🇨🇾"),
        ("GR", "希腊", "🇬🇷"),
        ("CN", "中国", "🇨🇳"),
        ("SEA", "东南亚", "🌏"),
        ("SAS", "南亚", "🇮🇳"),
        ("SAM", "南美洲", "🌎"),
        ("CAM", "中美洲", "🌎"),
        ("ME", "中东", "🕌"),
        ("SPARSE", "其他地区", "🌍"),
        ("OTHER", "未识别", "🏳️")
    ]

    private static let keywordMap: [(keyword: String, code: String)] = [
        ("港澳台", "GAT"), ("港澳", "GAT"), ("港台", "GAT"), ("台港澳", "GAT"),
        ("日韩", "JK"), ("韩日", "JK"),
        ("澳新", "ANZ"), ("新澳", "ANZ"),
        ("美加", "USCA"), ("北美", "USCA"),
        ("欧洲", "EU"), ("欧盟", "EU"),
        ("非洲", "AF"),
        ("独联体", "CIS"),
        ("香港", "HK"), ("澳门", "MO"), ("台灣", "TW"), ("台湾", "TW"),
        ("新加坡", "SG"), ("日本", "JP"), ("韩国", "KR"), ("韓國", "KR"),
        ("美国", "US"), ("美國", "US"), ("加拿大", "CA"), ("墨西哥", "MX"),
        ("英国", "GB"), ("英國", "GB"), ("爱尔兰", "IE"), ("愛爾蘭", "IE"),
        ("法国", "FR"), ("法國", "FR"), ("德国", "DE"), ("德國", "DE"),
        ("荷兰", "NL"), ("荷蘭", "NL"), ("比利时", "BE"), ("比利時", "BE"),
        ("瑞士", "CH"), ("奥地利", "AT"), ("奧地利", "AT"),
        ("意大利", "IT"), ("西班牙", "ES"), ("葡萄牙", "PT"),
        ("瑞典", "SE"), ("挪威", "NO"), ("芬兰", "FI"), ("芬蘭", "FI"), ("丹麦", "DK"), ("丹麥", "DK"),
        ("波兰", "PL"), ("波蘭", "PL"), ("捷克", "CZ"), ("匈牙利", "HU"),
        ("罗马尼亚", "RO"), ("羅馬尼亞", "RO"), ("乌克兰", "UA"), ("烏克蘭", "UA"),
        ("俄罗斯", "RU"), ("俄羅斯", "RU"), ("土耳其", "TR"),
        ("阿联酋", "AE"), ("阿聯酋", "AE"), ("迪拜", "AE"), ("沙特", "SA"), ("以色列", "IL"),
        ("印度", "IN"), ("巴基斯坦", "PK"), ("孟加拉", "BD"), ("斯里兰卡", "LK"),
        ("泰国", "TH"), ("泰國", "TH"), ("越南", "VN"), ("菲律宾", "PH"), ("菲律賓", "PH"),
        ("马来西亚", "MY"), ("馬來西亞", "MY"), ("印尼", "ID"), ("印度尼西亚", "ID"),
        ("柬埔寨", "KH"), ("缅甸", "MM"), ("老挝", "LA"), ("文莱", "BN"),
        ("东南亚", "SEA"), ("東南亞", "SEA"),
        ("南亚", "SAS"), ("南亞", "SAS"),
        ("南美", "SAM"), ("南美洲", "SAM"),
        ("中美", "CAM"), ("中美洲", "CAM"),
        ("中东", "ME"), ("中東", "ME"),
        ("马尔代夫", "MV"), ("不丹", "BT"), ("尼泊尔", "NP"), ("蒙古", "MN"),
        ("澳大利亚", "AU"), ("澳洲", "AU"), ("新西兰", "NZ"), ("斐济", "FJ"),
        ("阿根廷", "AR"), ("巴西", "BR"), ("智利", "CL"), ("秘鲁", "PE"), ("祕魯", "PE"),
        ("哥伦比亚", "CO"), ("烏拉圭", "UY"), ("乌拉圭", "UY"), ("巴拉圭", "PY"), ("玻利维亚", "BO"),
        ("厄瓜多尔", "EC"), ("委内瑞拉", "VE"),
        ("尼日利亚", "NG"), ("埃及", "EG"), ("南非", "ZA"),
        ("安道尔", "AD"), ("马耳他", "MT"), ("冰岛", "IS"),
        ("英属印度洋", "IO"), ("英屬印度洋", "IO")
    ]

    private static let preferredOrder = [
        "GAT", "JK", "ANZ", "SEA", "SAS", "USCA", "MX", "EU", "ME", "SAM", "CAM", "AF", "CIS",
        "GB", "DE", "FR", "NL", "CH", "IT", "ES", "SG", "TH", "VN", "PH", "MY", "ID",
    ]

    private static var codeLookup: [String: (title: String, flag: String)] = {
        var map: [String: (String, String)] = [:]
        for item in codeTitles {
            map[item.code] = (item.title, item.flag)
        }
        return map
    }()

    /// Raw country (or OTHER) — used for search hints.
    static func classify(_ name: String) -> (key: String, title: String, flag: String) {
        let raw = rawCountry(of: name)
        let region = regionBucket(raw)
        if let meta = codeLookup[region] {
            return (region, meta.title, meta.flag)
        }
        if let meta = codeLookup[raw] {
            return (raw, meta.title, meta.flag)
        }
        return ("OTHER", "未识别", "🏳️")
    }

    /// Display group key for a node given the full node list (SEA merge + singleton fold).
    static func displayGroup(for name: String, among nodes: [ProxyNode]) -> (key: String, title: String, flag: String) {
        let map = displayGroups(among: nodes)
        return map[name] ?? ("OTHER", "未识别", "🏳️")
    }

    /// Batch: nodeName → display group meta (computed once).
    static func displayGroups(among nodes: [ProxyNode]) -> [String: (key: String, title: String, flag: String)] {
        let assignment = groupKeyByNodeName(among: nodes)
        var result: [String: (key: String, title: String, flag: String)] = [:]
        for (name, key) in assignment {
            let m = meta(for: key) ?? ("未识别", "🏳️")
            result[name] = (key, m.title, m.flag)
        }
        return result
    }

    /// Fixed chip strip keys — always shown on iOS Nodes page (count may be 0).
    private static let fixedChipKeys = [
        "GAT", "JK", "ANZ", "SEA", "SAS", "USCA", "EU", "MX", "ME", "SAM", "AF", "OTHER",
    ]

    /// Stable region chips for UI: preferred fixed set + any extra groups present in `nodes`.
    static func fixedChipSummaries(among nodes: [ProxyNode]) -> [(key: String, title: String, flag: String, count: Int)] {
        let live = groups(from: nodes, sortByDelay: false)
        var countByKey: [String: Int] = [:]
        for g in live { countByKey[g.key] = g.nodes.count }

        var keys = fixedChipKeys
        for g in live where !keys.contains(g.key) && g.key != "SPARSE" {
            keys.append(g.key)
        }
        if (countByKey["SPARSE"] ?? 0) > 0 {
            keys.append("SPARSE")
        }

        return keys.compactMap { key in
            guard let m = meta(for: key) else { return nil }
            return (key: key, title: m.title, flag: m.flag, count: countByKey[key] ?? 0)
        }
    }

    static func groups(from nodes: [ProxyNode], sortByDelay: Bool) -> [Group] {
        let assignment = groupKeyByNodeName(among: nodes)
        var buckets: [String: [ProxyNode]] = [:]

        for node in nodes {
            let key = assignment[node.name] ?? "OTHER"
            buckets[key, default: []].append(node)
        }

        for key in buckets.keys {
            if sortByDelay {
                buckets[key]?.sort(by: delaySort)
            } else {
                buckets[key]?.sort { $0.name < $1.name }
            }
        }

        let keys = buckets.keys.sorted { lhs, rhs in
            let li = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let ri = preferredOrder.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            let lRank = (lhs == "SPARSE" ? 1 : 0) + (lhs == "OTHER" ? 2 : 0)
            let rRank = (rhs == "SPARSE" ? 1 : 0) + (rhs == "OTHER" ? 2 : 0)
            if lRank != rRank { return lRank < rRank }
            let lt = meta(for: lhs)?.title ?? lhs
            let rt = meta(for: rhs)?.title ?? rhs
            return lt.localizedStandardCompare(rt) == .orderedAscending
        }

        return keys.compactMap { key in
            guard let list = buckets[key], let m = meta(for: key) else { return nil }
            return Group(key: key, title: m.title, flag: m.flag, nodes: list)
        }
    }

    // MARK: - Grouping

    /// nodeName → display group key
    private static func groupKeyByNodeName(among nodes: [ProxyNode]) -> [String: String] {
        var byCountry: [String: [ProxyNode]] = [:]
        for node in nodes {
            let country = rawCountry(of: node.name)
            byCountry[country, default: []].append(node)
        }

        var byRegion: [String: [ProxyNode]] = [:]
        for (country, list) in byCountry {
            let region = regionBucket(country)
            byRegion[region, default: []].append(contentsOf: list)
        }

        var finalKeyForRegion: [String: String] = [:]
        for (region, list) in byRegion {
            if list.count <= 1, !majorCodes.contains(region) {
                finalKeyForRegion[region] = "SPARSE"
            } else {
                finalKeyForRegion[region] = region
            }
        }

        var result: [String: String] = [:]
        for node in nodes {
            let country = rawCountry(of: node.name)
            let region = regionBucket(country)
            result[node.name] = finalKeyForRegion[region] ?? region
        }
        return result
    }

    private static func regionBucket(_ country: String) -> String {
        if ["GAT", "JK", "ANZ", "SEA", "SAS", "SAM", "CAM", "ME", "USCA", "EU", "AF", "CIS"].contains(country) {
            return country
        }
        if gatCodes.contains(country) { return "GAT" }
        if jkCodes.contains(country) { return "JK" }
        if anzCodes.contains(country) { return "ANZ" }
        if uscaCodes.contains(country) { return "USCA" }
        if euCodes.contains(country) { return "EU" }
        if afCodes.contains(country) { return "AF" }
        if cisCodes.contains(country) { return "CIS" }
        if seaCodes.contains(country) { return "SEA" }
        if sasCodes.contains(country) { return "SAS" }
        if samCodes.contains(country) { return "SAM" }
        if camCodes.contains(country) { return "CAM" }
        if meCodes.contains(country) { return "ME" }
        if country == "UK" { return "GB" }
        return country
    }

    private static func meta(for key: String) -> (title: String, flag: String)? {
        codeLookup[key]
    }

    private static func rawCountry(of name: String) -> String {
        for item in keywordMap where name.contains(item.keyword) {
            return item.code
        }

        if let code = trailingCountryCode(in: name), codeLookup[code] != nil {
            return code
        }

        if let fromFlag = regionFromFlagEmoji(in: name), codeLookup[fromFlag] != nil {
            return fromFlag
        }

        return "OTHER"
    }

    private static func trailingCountryCode(in name: String) -> String? {
        let pattern = #"\b([A-Z]{2})\b\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              let codeRange = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[codeRange])
    }

    private static func regionFromFlagEmoji(in name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2 else { return nil }
        let base: UInt32 = 0x1F1E6
        for i in 0..<(scalars.count - 1) {
            let a = scalars[i].value
            let b = scalars[i + 1].value
            if (0x1F1E6...0x1F1FF).contains(a), (0x1F1E6...0x1F1FF).contains(b) {
                let c1 = Character(UnicodeScalar(65 + (a - base))!)
                let c2 = Character(UnicodeScalar(65 + (b - base))!)
                return "\(c1)\(c2)"
            }
        }
        return nil
    }

    private static func delaySort(_ lhs: ProxyNode, _ rhs: ProxyNode) -> Bool {
        func rank(_ ms: Int?) -> Int {
            guard let ms else { return 1_000_000_000 }
            if ms < 0 { return 1_000_000_001 }
            return ms
        }
        let a = rank(lhs.delayMs)
        let b = rank(rhs.delayMs)
        if a != b { return a < b }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
