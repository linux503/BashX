import AppKit
import Foundation

enum AppUpdateService {
    static let repoOwner = "linux503"
    static let repoName = "BashX"
    /// Same page as README — Settings → About → Open releases.
    static let releasesPage = "https://github.com/linux503/BashX/releases"
    static let releasesLatestPage = "https://github.com/linux503/BashX/releases/latest"
    /// Stable asset name on every release (plus versioned BashX-x.y.z.dmg).
    static let latestAssetName = "BashX.dmg"

    struct ReleaseInfo: Sendable, Equatable {
        let version: String
        let tag: String
        let downloadURL: URL
        let fileName: String
        let fileSize: Int64
        let publishedAt: Date?
        let releaseNotes: String?
    }

    enum UpdateError: LocalizedError {
        case httpError(status: Int, message: String)
        case badResponse(String)
        case noRelease
        case noAsset

        var errorDescription: String? {
            switch self {
            case .httpError(let status, let message):
                if status == 403, message.localizedCaseInsensitiveContains("rate limit") {
                    return "GitHub 请求过于频繁，请稍后再试或打开发布页手动下载"
                }
                if status == 404 {
                    return "未找到 GitHub 发布版本"
                }
                return message.isEmpty ? "GitHub 返回错误（HTTP \(status)）" : message
            case .badResponse(let detail):
                return detail
            case .noRelease:
                return "暂无可用发布版本"
            case .noAsset:
                return "最新发布中未找到 DMG 安装包"
            }
        }
    }

    /// Bypass system proxy — update check must work even when BashX proxy is on or misconfigured.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
        ]
        return URLSession(configuration: config)
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        // Prefer /releases/latest, then scan recent releases for a DMG asset.
        if let latest = try await fetchJSONRelease(
            url: URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        ) {
            return latest
        }

        let listURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=15")!
        let (data, response) = try await apiRequest(listURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw parseAPIError(data: data, response: response) ?? UpdateError.badResponse("无法读取 GitHub 发布列表")
        }
        guard let items = decodeJSONArray(data) else {
            throw invalidBodyError(data: data, http: http)
        }

        for item in items {
            if (item["draft"] as? Bool) == true { continue }
            if (item["prerelease"] as? Bool) == true { continue }
            if let info = parseReleaseJSON(item) { return info }
        }
        throw UpdateError.noRelease
    }

    static func compareVersion(_ remote: String, to current: String) -> ComparisonResult {
        let a = normalizeVersion(remote).split(separator: ".").map { Int($0) ?? 0 }
        let b = normalizeVersion(current).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return .orderedDescending }
            if av < bv { return .orderedAscending }
        }
        return .orderedSame
    }

    static func isNewerVersion(_ remote: String, than current: String) -> Bool {
        compareVersion(remote, to: current) == .orderedDescending
    }

    static func downloadRelease(
        _ info: ReleaseInfo,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let updatesDir = Paths.supportDir.appendingPathComponent("updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        let dest = updatesDir.appendingPathComponent(info.fileName)

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        progress(0.02)

        var request = URLRequest(url: info.downloadURL, timeoutInterval: 600)
        request.setValue("BashX/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (tempURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.httpError(status: code, message: "下载安装包失败")
        }

        progress(0.92)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        stripQuarantine(at: dest)
        progress(1)
        return dest
    }

    static func openInstaller(_ dmgURL: URL) {
        stripQuarantine(at: dmgURL)
        NSWorkspace.shared.open(dmgURL)
    }

    static func openReleasesPage() {
        if let url = URL(string: releasesPage) {
            NSWorkspace.shared.open(url)
        }
    }

    static func formatSize(_ bytes: Int64) -> String {
        ByteFormat.size(bytes)
    }

    // MARK: - Private

    private static func fetchJSONRelease(url: URL) async throws -> ReleaseInfo? {
        let (data, response) = try await apiRequest(url)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse("GitHub 响应无效")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 { return nil }
            throw parseAPIError(data: data, response: response) ?? UpdateError.badResponse("GitHub 返回 HTTP \(http.statusCode)")
        }
        guard let json = decodeJSONObject(data) else {
            // 200 but HTML/empty — usually system proxy or network filter.
            throw invalidBodyError(data: data, http: http)
        }
        return parseReleaseJSON(json)
    }

    private static func decodeJSONObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return nil
    }

    private static func decodeJSONArray(_ data: Data) -> [[String: Any]]? {
        guard !data.isEmpty else { return nil }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }
        return nil
    }

    private static func invalidBodyError(data: Data, http: HTTPURLResponse) -> UpdateError {
        let snippet = String(data: data.prefix(120), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if snippet.hasPrefix("<") {
            return .badResponse("GitHub 返回了网页而非 JSON（HTTP \(http.statusCode)）。请暂时关闭系统代理后重试，或点「打开发布页」手动下载。")
        }
        if snippet.isEmpty {
            return .badResponse("GitHub 返回空响应（HTTP \(http.statusCode)）。请检查网络连接。")
        }
        return .badResponse("无法解析 GitHub 发布信息（HTTP \(http.statusCode)）")
    }

    private static func apiRequest(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("BashX/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    private static func parseAPIError(data: Data, response: URLResponse) -> UpdateError? {
        guard let http = response as? HTTPURLResponse else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String, !message.isEmpty {
            return .httpError(status: http.statusCode, message: message)
        }
        return .httpError(status: http.statusCode, message: "")
    }

    private static func parseReleaseJSON(_ json: [String: Any]) -> ReleaseInfo? {
        let tag = (json["tag_name"] as? String) ?? ""
        let version = normalizeVersion(tag)
        guard !version.isEmpty else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let dmg = pickDMGAsset(from: assets, version: version),
              let urlString = dmg["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString),
              let fileName = dmg["name"] as? String else {
            return nil
        }

        let size = int64Value(dmg["size"]) ?? 0
        let publishedRaw = json["published_at"] as? String
        let publishedAt = publishedRaw.flatMap { iso8601.date(from: $0) ?? iso8601Fallback.date(from: $0) }
        let notes = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ReleaseInfo(
            version: version,
            tag: tag,
            downloadURL: downloadURL,
            fileName: fileName,
            fileSize: size,
            publishedAt: publishedAt,
            releaseNotes: notes?.isEmpty == false ? notes : nil
        )
    }

    private static func pickDMGAsset(from assets: [[String: Any]], version: String) -> [String: Any]? {
        let dmgs = assets.filter { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        guard !dmgs.isEmpty else { return nil }
        if let stable = dmgs.first(where: { ($0["name"] as? String) == latestAssetName }) {
            return stable
        }
        if let matched = dmgs.first(where: { ($0["name"] as? String)?.contains(version) == true }) {
            return matched
        }
        return dmgs.max {
            (int64Value($0["size"]) ?? 0) < (int64Value($1["size"]) ?? 0)
        }
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let i = value as? Int { return Int64(i) }
        if let i = value as? Int64 { return i }
        return nil
    }

    private static func normalizeVersion(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func stripQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    static let shared = AppUpdateController()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(remote: String)
        case ahead(remote: String)
        case available(AppUpdateService.ReleaseInfo)
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?

    private init() {}

    func check(silent: Bool = false) async {
        phase = .checking
        do {
            let release = try await AppUpdateService.fetchLatestRelease()
            lastChecked = Date()
            switch AppUpdateService.compareVersion(release.version, to: AppVersion.short) {
            case .orderedDescending:
                phase = .available(release)
            case .orderedSame:
                phase = .upToDate(remote: release.version)
            case .orderedAscending:
                phase = .ahead(remote: release.version)
            }
        } catch {
            lastChecked = Date()
            phase = .failed(error.localizedDescription)
            if !silent {
                NSLog("BashX update check failed: \(error.localizedDescription)")
            }
        }
    }

    func downloadAndInstall() async {
        guard case .available(let info) = phase else { return }
        phase = .downloading(progress: 0)
        do {
            let local = try await AppUpdateService.downloadRelease(info) { [weak self] p in
                Task { @MainActor in
                    self?.phase = .downloading(progress: p)
                }
            }
            phase = .downloaded(local)
            AppUpdateService.openInstaller(local)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func openReleasesPage() {
        AppUpdateService.openReleasesPage()
    }
}
