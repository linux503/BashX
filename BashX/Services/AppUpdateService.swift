import AppKit
import Foundation

enum AppUpdateService {
    static let repoOwner = "linux503"
    static let repoName = "BashX"
    static let releasesPage = "https://github.com/linux503/BashX/releases"

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
        case badResponse
        case noAsset
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .badResponse: return "无法解析 GitHub 发布信息"
            case .noAsset: return "未找到 DMG 安装包"
            case .downloadFailed: return "下载失败"
            }
        }
    }

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("BashX/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.badResponse
        }

        let tag = (json["tag_name"] as? String) ?? ""
        let version = normalizeVersion(tag)
        guard !version.isEmpty else { throw UpdateError.badResponse }

        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let urlString = dmg["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString),
              let fileName = dmg["name"] as? String else {
            throw UpdateError.noAsset
        }

        let size = (dmg["size"] as? NSNumber)?.int64Value ?? 0
        let publishedAt = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let notes = json["body"] as? String

        return ReleaseInfo(
            version: version,
            tag: tag,
            downloadURL: downloadURL,
            fileName: fileName,
            fileSize: size,
            publishedAt: publishedAt,
            releaseNotes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func isNewerVersion(_ remote: String, than current: String) -> Bool {
        compareVersion(remote, current) == .orderedDescending
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

        let (tempURL, response) = try await URLSession.shared.download(from: info.downloadURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
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

    private static func normalizeVersion(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = normalizeVersion(lhs).split(separator: ".").map { Int($0) ?? 0 }
        let b = normalizeVersion(rhs).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return .orderedDescending }
            if av < bv { return .orderedAscending }
        }
        return .orderedSame
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
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppUpdateService.ReleaseInfo)
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?

    func check(silent: Bool = false) async {
        phase = .checking
        do {
            let release = try await AppUpdateService.fetchLatestRelease()
            lastChecked = Date()
            if AppUpdateService.isNewerVersion(release.version, than: AppVersion.short) {
                phase = .available(release)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = silent ? .idle : .failed(error.localizedDescription)
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
