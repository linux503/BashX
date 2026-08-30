import Foundation

/// Geo routing fallback — Shadowrocket / Surge / Clash Verge (ACL4SSR) pattern.
///
/// Standard tail (industry top 3):
/// 1. GEOSITE,gfw + geolocation-!cn → PROXY
/// 2. GEOIP,CN → DIRECT
/// 3. GEOIP,!CN or MATCH → PROXY（漏网之鱼 / 无法判断 → 代理）
enum RoutingGeoRules {
    /// Mac: full GEOSITE + GEOIP (needs geoip.metadb + geosite.dat in mihomo home).
    static let macWithGeoDB: [String] = [
        "GEOSITE,private,DIRECT",
        "GEOSITE,gfw,PROXY",
        "GEOSITE,greatfire,PROXY",
        "GEOSITE,geolocation-!cn,PROXY",
        "GEOSITE,tld-!cn,PROXY",
        "GEOSITE,category-social-media-!cn,PROXY",
        "GEOSITE,category-media,PROXY",
        "GEOSITE,category-dev,PROXY",
        "GEOSITE,cloudflare,PROXY",
        "GEOIP,PRIVATE,DIRECT,no-resolve",
        "GEOIP,CN,DIRECT,no-resolve",
        "GEOIP,!CN,PROXY,no-resolve",
    ]

    /// Mac without geo DB yet — domain TLD fallback only.
    static let macLite: [String] = foreignTLDProxy + [
        "MATCH,PROXY",
    ]

    /// iOS NE: no geo DB (memory / jetsam) — TLD + MATCH,PROXY.
    static let iosLite: [String] = foreignTLDProxy + [
        "MATCH,PROXY",
    ]

    /// Foreign TLD catch-all when GEOSITE,tld-!cn unavailable.
    /// Placed after chinaDirect — known CN domains already matched.
    private static let foreignTLDProxy: [String] = [
        "DOMAIN-SUFFIX,com,PROXY",
        "DOMAIN-SUFFIX,net,PROXY",
        "DOMAIN-SUFFIX,org,PROXY",
        "DOMAIN-SUFFIX,io,PROXY",
        "DOMAIN-SUFFIX,co,PROXY",
        "DOMAIN-SUFFIX,app,PROXY",
        "DOMAIN-SUFFIX,dev,PROXY",
        "DOMAIN-SUFFIX,xyz,PROXY",
        "DOMAIN-SUFFIX,info,PROXY",
        "DOMAIN-SUFFIX,biz,PROXY",
        "DOMAIN-SUFFIX,cc,PROXY",
        "DOMAIN-SUFFIX,tv,PROXY",
        "DOMAIN-SUFFIX,me,PROXY",
        "DOMAIN-SUFFIX,uk,PROXY",
        "DOMAIN-SUFFIX,de,PROXY",
        "DOMAIN-SUFFIX,jp,PROXY",
        "DOMAIN-SUFFIX,kr,PROXY",
        "DOMAIN-SUFFIX,fr,PROXY",
        "DOMAIN-SUFFIX,au,PROXY",
        "DOMAIN-SUFFIX,ca,PROXY",
        "DOMAIN-SUFFIX,us,PROXY",
        "DOMAIN-SUFFIX,ru,PROXY",
        "DOMAIN-SUFFIX,in,PROXY",
        "DOMAIN-SUFFIX,sg,PROXY",
        "DOMAIN-SUFFIX,hk,PROXY",
        "DOMAIN-SUFFIX,tw,PROXY",
        "DOMAIN-SUFFIX,nl,PROXY",
        "DOMAIN-SUFFIX,it,PROXY",
        "DOMAIN-SUFFIX,es,PROXY",
        "DOMAIN-SUFFIX,se,PROXY",
        "DOMAIN-SUFFIX,ch,PROXY",
        "DOMAIN-SUFFIX,at,PROXY",
        "DOMAIN-SUFFIX,be,PROXY",
        "DOMAIN-SUFFIX,pl,PROXY",
        "DOMAIN-SUFFIX,cz,PROXY",
        "DOMAIN-SUFFIX,fi,PROXY",
        "DOMAIN-SUFFIX,no,PROXY",
        "DOMAIN-SUFFIX,dk,PROXY",
        "DOMAIN-SUFFIX,ie,PROXY",
        "DOMAIN-SUFFIX,nz,PROXY",
        "DOMAIN-SUFFIX,br,PROXY",
        "DOMAIN-SUFFIX,mx,PROXY",
        "DOMAIN-SUFFIX,ar,PROXY",
        "DOMAIN-SUFFIX,cl,PROXY",
        "DOMAIN-SUFFIX,za,PROXY",
        "DOMAIN-SUFFIX,ae,PROXY",
        "DOMAIN-SUFFIX,il,PROXY",
        "DOMAIN-SUFFIX,tr,PROXY",
        "DOMAIN-SUFFIX,th,PROXY",
        "DOMAIN-SUFFIX,vn,PROXY",
        "DOMAIN-SUFFIX,id,PROXY",
        "DOMAIN-SUFFIX,my,PROXY",
        "DOMAIN-SUFFIX,ph,PROXY",
        "DOMAIN-SUFFIX,pw,PROXY",
        "DOMAIN-SUFFIX,gg,PROXY",
        "DOMAIN-SUFFIX,fm,PROXY",
        "DOMAIN-SUFFIX,am,PROXY",
        "DOMAIN-SUFFIX,ly,PROXY",
        "DOMAIN-SUFFIX,to,PROXY",
        "DOMAIN-SUFFIX,sh,PROXY",
        "DOMAIN-SUFFIX,vc,PROXY",
        "DOMAIN-SUFFIX,ai,PROXY",
        "DOMAIN-SUFFIX,cloud,PROXY",
        "DOMAIN-SUFFIX,tech,PROXY",
        "DOMAIN-SUFFIX,online,PROXY",
        "DOMAIN-SUFFIX,site,PROXY",
        "DOMAIN-SUFFIX,store,PROXY",
        "DOMAIN-SUFFIX,shop,PROXY",
        "DOMAIN-SUFFIX,live,PROXY",
        "DOMAIN-SUFFIX,pro,PROXY",
        "DOMAIN-SUFFIX,wiki,PROXY",
    ]

    static func tail(useGeoDB: Bool) -> [String] {
        #if os(macOS)
        if useGeoDB {
            return macWithGeoDB + ["MATCH,PROXY"]
        }
        return macLite
        #else
        return iosLite
        #endif
    }

    /// Skip duplicate GEOSITE/GEOIP/MATCH from bundled smart rules — injected centrally.
    static func shouldSkipBaseRule(_ rule: String) -> Bool {
        let u = rule.trimmingCharacters(in: .whitespaces).uppercased()
        if u.hasPrefix("MATCH,") { return true }
        #if os(iOS)
        if u.hasPrefix("GEOSITE,") || u.hasPrefix("GEOIP,") { return true }
        #else
        if u.hasPrefix("GEOSITE,") {
            let site = geositeName(u) ?? ""
            if macGeoSites.contains(site) { return true }
        }
        if u.hasPrefix("GEOIP,") {
            let code = geoipCode(u) ?? ""
            if macGeoCodes.contains(code) { return true }
        }
        // Skip foreign TLD lines from smart rules — covered by tail or proxyFirst.
        // Keep explicit .tv — must not rely on GEOSITE,tld-!cn alone.
        if u.hasPrefix("DOMAIN-SUFFIX,") {
            let parts = u.split(separator: ",")
            if parts.count >= 2 {
                let tld = String(parts[1])
                if tld != "tv", foreignTLDS.contains(tld) {
                    return true
                }
            }
        }
        #endif
        return false
    }

    private static let macGeoSites: Set<String> = [
        "private", "gfw", "greatfire", "geolocation-!cn", "tld-!cn",
        "category-social-media-!cn", "category-media", "category-dev", "cloudflare",
    ]

    private static let macGeoCodes: Set<String> = [
        "PRIVATE", "CN", "!CN",
    ]

    private static let foreignTLDS: Set<String> = {
        Set(foreignTLDProxy.compactMap { rule -> String? in
            let u = rule.uppercased()
            guard u.hasPrefix("DOMAIN-SUFFIX,") else { return nil }
            let parts = u.split(separator: ",")
            return parts.count >= 2 ? String(parts[1]) : nil
        })
    }()

    private static func geositeName(_ upper: String) -> String? {
        let parts = upper.split(separator: ",")
        guard parts.count >= 2, parts[0] == "GEOSITE" else { return nil }
        return String(parts[1])
    }

    private static func geoipCode(_ upper: String) -> String? {
        let parts = upper.split(separator: ",")
        guard parts.count >= 2, parts[0] == "GEOIP" else { return nil }
        return String(parts[1])
    }
}
