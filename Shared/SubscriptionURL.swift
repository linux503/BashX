import Foundation

enum SubscriptionURL {
    /// Strip invisible / line-break junk common in QR payloads.
    private static func scrub(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    /// Normalize pasted subscription links (trim, optional https prefix, http/https only).
    static func normalized(_ raw: String, allowInsecureHTTP: Bool = true) -> String? {
        var trimmed = scrub(raw)
        guard !trimmed.isEmpty else { return nil }

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
    static func extracted(from raw: String) -> String? {
        var trimmed = scrub(raw)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("%"), let decoded = trimmed.removingPercentEncoding, !decoded.isEmpty {
            trimmed = scrub(decoded)
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                return normalized(trimmed, allowInsecureHTTP: true)
            }
            if scheme == "bashx" || scheme == "clash" || scheme == "clashmeta" || scheme == "sub" || scheme == "surge" {
                if let sub = url.queryItems?.first(where: { $0.name == "url" })?.value {
                    return extracted(from: sub)
                }
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !path.isEmpty {
                    return extracted(from: path)
                }
            }
        }

        // Bare domain/path from QR, e.g. example.com/sub/abc
        return normalized(trimmed, allowInsecureHTTP: true)
    }
}

private extension URL {
    var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
