import Foundation

enum SubscriptionURL {
    /// Strip invisible / line-break junk common in QR payloads.
    private static func scrub(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Soft scrub that keeps spaces inside URLs' query when already decoded.
    private static func softScrub(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    /// Normalize pasted subscription links (trim, optional https prefix, http/https only).
    static func normalized(_ raw: String, allowInsecureHTTP: Bool = true) -> String? {
        var trimmed = softScrub(raw)
        guard !trimmed.isEmpty else { return nil }

        // Accept base64-wrapped plain URLs (common QR export).
        if looksLikeBase64Payload(trimmed),
           let decoded = decodeFlexibleBase64String(trimmed),
           let nested = normalized(decoded, allowInsecureHTTP: allowInsecureHTTP) {
            return nested
        }

        let lower = trimmed.lowercased()
        if !lower.hasPrefix("http://"), !lower.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }

        let scheme = trimmed.lowercased()
        if scheme.hasPrefix("https://") { return trimmed }
        if scheme.hasPrefix("http://") {
            return allowInsecureHTTP ? trimmed : nil
        }
        return nil
    }

    /// Parse QR / clipboard / deep-link payloads into a subscription URL.
    /// Supports: http(s), bashx/clash/sub deep links, `sub://` + base64(url), raw base64(url).
    static func extracted(from raw: String) -> String? {
        var trimmed = softScrub(raw)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("%"), let decoded = trimmed.removingPercentEncoding, !decoded.isEmpty {
            trimmed = softScrub(decoded)
        }

        // sub://BASE64(url)  /  subscription://BASE64(url)
        if let fromSubScheme = extractSubSchemeBase64(trimmed) {
            return fromSubScheme
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                return normalized(trimmed, allowInsecureHTTP: true)
            }
            if scheme == "bashx" || scheme == "clash" || scheme == "clashmeta"
                || scheme == "sub" || scheme == "surge" || scheme == "shadowrocket" {
                if let sub = url.queryItems?.first(where: {
                    ["url", "link", "subscription"].contains($0.name.lowercased())
                })?.value {
                    return extracted(from: sub)
                }
                // Some QRs put base64 in the host/path: clash://BASE64...
                let hostPath = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
                if !hostPath.isEmpty, let nested = extracted(from: hostPath) {
                    return nested
                }
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !path.isEmpty {
                    return extracted(from: path)
                }
            }
        }

        // Pure base64 of an http(s) URL (with or without padding / URL-safe alphabet).
        if looksLikeBase64Payload(trimmed),
           let decoded = decodeFlexibleBase64String(trimmed) {
            let soft = softScrub(decoded)
            if soft.lowercased().contains("http://") || soft.lowercased().contains("https://")
                || soft.lowercased().hasPrefix("sub://")
                || soft.lowercased().hasPrefix("clash://")
                || soft.lowercased().hasPrefix("bashx://") {
                if let nested = extracted(from: soft) {
                    return nested
                }
            }
            // Decoded text may itself be a bare domain/path.
            if let nested = normalized(soft, allowInsecureHTTP: true) {
                return nested
            }
        }

        // Bare domain/path from QR, e.g. example.com/sub/abc
        return normalized(trimmed, allowInsecureHTTP: true)
    }

    // MARK: - Base64 helpers

    /// `sub://xxxx` where xxxx is base64(url) — used by many airport QR codes.
    private static func extractSubSchemeBase64(_ raw: String) -> String? {
        let lower = raw.lowercased()
        let prefixes = ["sub://", "subscription://", "clash://install-config?url="]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let rest = String(raw.dropFirst(prefix.count))
            if prefix.contains("url=") {
                return extracted(from: rest.removingPercentEncoding ?? rest)
            }
            let payload = rest
                .trimmingCharacters(in: CharacterSet(charactersIn: "/#"))
                .removingPercentEncoding ?? rest
            if let decoded = decodeFlexibleBase64String(payload) {
                return extracted(from: decoded) ?? normalized(decoded, allowInsecureHTTP: true)
            }
            // Sometimes the rest is already a plain URL.
            return extracted(from: payload)
        }
        return nil
    }

    private static func looksLikeBase64Payload(_ raw: String) -> Bool {
        let s = scrub(raw)
        // Too short / already a URL → skip
        guard s.count >= 16 else { return false }
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return false }
        if lower.hasPrefix("sub://") || lower.hasPrefix("clash://") || lower.hasPrefix("bashx://") {
            return false
        }
        // Allow standard + URL-safe base64 alphabet
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-=\n\r")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func decodeFlexibleBase64String(_ raw: String) -> String? {
        guard let data = decodeFlexibleBase64(raw) else { return nil }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private static func decodeFlexibleBase64(_ raw: String) -> Data? {
        var s = scrub(raw)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - (s.count % 4)) % 4
        if pad > 0 { s += String(repeating: "=", count: pad) }
        return Data(base64Encoded: s, options: [.ignoreUnknownCharacters])
    }
}

private extension URL {
    var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
