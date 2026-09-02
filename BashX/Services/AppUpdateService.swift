import AppKit
import Foundation

enum AppUpdateService {
    static let repoOwner = "linux503"
    static let repoName = "BashX"
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
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .httpError(let status, let message):
                if status == 403, message.localizedCaseInsensitiveContains("rate limit") {
                    return "暂时无法检查更新，请稍后再试"
                }
                if status == 404 {
                    return "未找到可用更新"
                }
                return message.isEmpty ? "检查更新失败（HTTP \(status)）" : message
            case .badResponse(let detail):
                return detail
            case .noRelease:
                return "暂无可用发布版本"
            case .noAsset:
                return "最新版本中未找到安装包"
            case .downloadFailed(let detail):
                return detail
            }
        }
    }

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

    // MARK: - Public

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        let endpoints = releaseAPIEndpoints()
        var lastError: Error?

        for session in makeSessions() {
            for url in endpoints {
                do {
                    if let info = try await fetchJSONRelease(url: url, session: session) {
                        return info
                    }
                } catch {
                    lastError = error
                }
            }

            // Scan recent releases if /latest had no DMG.
            do {
                if let info = try await fetchFromReleaseList(session: session) {
                    return info
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? UpdateError.noRelease
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

        let urls = downloadURLCandidates(for: info)
        var lastError: Error?
        progress(0.02)

        for session in makeSessions() {
            for url in urls {
                do {
                    let local = try await downloadFile(
                        from: url,
                        to: dest,
                        expectedSize: info.fileSize,
                        session: session,
                        progress: progress
                    )
                    stripQuarantine(at: local)
                    progress(1)
                    return local
                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: dest)
                }
            }
        }

        let detail = (lastError as? LocalizedError)?.errorDescription
            ?? lastError?.localizedDescription
            ?? "下载安装包失败"
        throw UpdateError.downloadFailed(detail)
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

    // MARK: - Sessions (system proxy → local mixed → direct)

    /// Order matters: when BashX system proxy / TUN is on, GitHub needs that path.
    /// Old code forced direct and failed in many CN networks.
    private static func makeSessions() -> [URLSession] {
        var sessions: [URLSession] = [session(proxy: .system)]
        if let port = localMixedPort(), port > 0, isTCPPortOpen(port) {
            sessions.append(session(proxy: .mixedPort(port)))
        }
        sessions.append(session(proxy: .direct))
        return sessions
    }

    private enum ProxyMode {
        case system
        case mixedPort(Int)
        case direct
    }

    private static func session(proxy: ProxyMode) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldUsePipelining = false

        switch proxy {
        case .system:
            break
        case .mixedPort(let port):
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .direct:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
            ]
        }
        return URLSession(configuration: config)
    }

    private static func localMixedPort() -> Int? {
        let port = SettingsStore.load().mixedPort
        return (1...65535).contains(port) ? port : nil
    }

    /// Avoid waiting on a dead 127.0.0.1:mixedPort when the core is off.
    private static func isTCPPortOpen(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                // Non-blocking connect with short timeout via SO_SNDTIMEO.
                var tv = timeval(tv_sec: 0, tv_usec: 200_000)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                return connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - Endpoints

    private static func releaseAPIEndpoints() -> [URL] {
        let latest = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        return [
            URL(string: latest)!,
            // Some networks reach github.com but not api.github.com — still try list via same host later.
        ]
    }

    private static func downloadURLCandidates(for info: ReleaseInfo) -> [URL] {
        var out: [URL] = [info.downloadURL]
        let raw = info.downloadURL.absoluteString
        // Common CN-friendly GitHub release mirrors.
        let mirrors = [
            "https://ghfast.top/\(raw)",
            "https://gh-proxy.com/\(raw)",
            "https://proxy.corpnerd.com/\(raw)",
        ]
        for m in mirrors {
            if let u = URL(string: m) { out.append(u) }
        }
        return out
    }

    // MARK: - Fetch

    private static func fetchFromReleaseList(session: URLSession) async throws -> ReleaseInfo? {
        let listURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=15")!
        let (data, response) = try await apiRequest(listURL, session: session)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw parseAPIError(data: data, response: response) ?? UpdateError.badResponse("无法读取更新列表")
        }
        guard let items = decodeJSONArray(data) else {
            throw invalidBodyError(data: data, http: http)
        }

        for item in items {
            if (item["draft"] as? Bool) == true { continue }
            if (item["prerelease"] as? Bool) == true { continue }
            if let info = parseReleaseJSON(item) { return info }
        }
        return nil
    }

    private static func fetchJSONRelease(url: URL, session: URLSession) async throws -> ReleaseInfo? {
        let (data, response) = try await apiRequest(url, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse("更新服务器响应无效")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 { return nil }
            throw parseAPIError(data: data, response: response)
                ?? UpdateError.badResponse("检查更新失败（HTTP \(http.statusCode)）")
        }
        guard let json = decodeJSONObject(data) else {
            throw invalidBodyError(data: data, http: http)
        }
        return parseReleaseJSON(json)
    }

    private static func downloadFile(
        from url: URL,
        to dest: URL,
        expectedSize: Int64,
        session: URLSession,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 900)
        request.setValue("BashX/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (tempURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.downloadFailed("下载响应无效")
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateError.downloadFailed("下载安装包失败（HTTP \(http.statusCode)）")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        // DMG should be multi-MB; reject empty / HTML error pages.
        if size < 1_000_000 {
            throw UpdateError.downloadFailed("下载文件异常（\(ByteFormat.size(size))），请重试")
        }
        if expectedSize > 1_000_000, size < expectedSize / 2 {
            throw UpdateError.downloadFailed("下载不完整，请重试")
        }

        progress(0.92)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private static func decodeJSONObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodeJSONArray(_ data: Data) -> [[String: Any]]? {
        guard !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func invalidBodyError(data: Data, http: HTTPURLResponse) -> UpdateError {
        let snippet = String(data: data.prefix(120), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if snippet.hasPrefix("<") {
            return .badResponse("无法获取更新信息，请确认网络或先连接节点后重试")
        }
        if snippet.isEmpty {
            return .badResponse("更新服务器无响应，请检查网络后重试")
        }
        return .badResponse("无法解析更新信息（HTTP \(http.statusCode)）")
    }

    private static func apiRequest(_ url: URL, session: URLSession) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("BashX/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            return try await session.data(for: request)
        } catch {
            throw UpdateError.badResponse(friendlyNetworkError(error))
        }
    }

    private static func friendlyNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return "连接更新服务器超时，请先连接节点或稍后重试"
            case NSURLErrorNotConnectedToInternet:
                return "网络未连接"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "无法解析更新服务器，请先连接节点后重试"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                return "无法连接更新服务器，请先连接节点后重试"
            case NSURLErrorSecureConnectionFailed:
                return "安全连接失败，请稍后重试"
            default:
                break
            }
        }
        return error.localizedDescription
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
        if let d = value as? Double { return Int64(d) }
        if let s = value as? String { return Int64(s) }
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
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
    /// Hidden for current launch after user taps close on the home banner.
    @Published private(set) var homeBannerDismissed = false

    private var checkedThisLaunch = false

    private init() {}

    var shouldShowHomeBanner: Bool {
        guard !homeBannerDismissed else { return false }
        switch phase {
        case .available, .downloading:
            return true
        default:
            return false
        }
    }

    func dismissHomeBanner() {
        homeBannerDismissed = true
    }

    /// Once per app launch — check GitHub releases and show home banner when newer.
    func checkForHomeBannerIfNeeded() async {
        guard !checkedThisLaunch else { return }
        checkedThisLaunch = true
        homeBannerDismissed = false
        await check(silent: true, autoInstall: false)
    }

    func check(silent: Bool = false, autoInstall: Bool = false) async {
        phase = .checking
        do {
            let release = try await AppUpdateService.fetchLatestRelease()
            lastChecked = Date()
            switch AppUpdateService.compareVersion(release.version, to: AppVersion.short) {
            case .orderedDescending:
                phase = .available(release)
                if autoInstall {
                    await downloadAndInstall()
                }
            case .orderedSame:
                phase = .upToDate(remote: release.version)
            case .orderedAscending:
                phase = .ahead(remote: release.version)
            }
        } catch {
            lastChecked = Date()
            if silent {
                phase = .idle
            } else {
                phase = .failed(error.localizedDescription)
            }
            NSLog("BashX update check failed: \(error.localizedDescription)")
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
            NSLog("BashX update download failed: \(error.localizedDescription)")
        }
    }
}
