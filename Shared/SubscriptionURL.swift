import Foundation

enum SubscriptionURL {
    /// Normalize pasted subscription links (trim, optional https prefix, http/https only).
    static func normalized(_ raw: String, allowInsecureHTTP: Bool = true) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
