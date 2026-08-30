import Foundation
import AppKit

enum ClashCore {
    /// Shared ephemeral session for local mihomo REST (avoids per-call allocation).
    private static let localAPISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func resolveBinary(customPath: String) -> String? {
        let candidates = [
            customPath,
            Paths.supportDir.appendingPathComponent("mihomo").path,
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo",
            "/opt/homebrew/bin/clash-meta",
            "/usr/local/bin/clash-meta",
            "/opt/homebrew/bin/clash",
            "/usr/local/bin/clash",
            Paths.supportDir.appendingPathComponent("clash").path
        ].filter { !$0.isEmpty }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    enum APIStatus: Equatable {
        case online
        case authFailed
        case unreachable
    }

    static func apiStatus(controller: String, secret: String = "") async -> APIStatus {
        guard let url = URL(string: "http://\(controller)/version") else { return .unreachable }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await localAPISession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            if http.statusCode == 401 { return .authFailed }
            return (200...299).contains(http.statusCode) ? .online : .unreachable
        } catch {
            return .unreachable
        }
    }

    static func isRunning(controller: String, secret: String = "") async -> Bool {
        await apiStatus(controller: controller, secret: secret) == .online
    }

    static func selectProxy(controller: String, secret: String, group: String, name: String) async throws {
        let encodedGroup = encodePath(group)
        let encodedNamePath = encodePath(name)
        // Prefer PUT /proxies/{group} with JSON body; fall back to path style if needed.
        guard let url = URL(string: "http://\(controller)/proxies/\(encodedGroup)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, response) = try await localAPISession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Some cores accept encoded name in path only for delay; keep error.
            _ = encodedNamePath
            throw URLError(.badServerResponse)
        }
    }

    /// Force url-test / fallback group to re-measure and pick the current best node.
    @discardableResult
    static func retestProxyGroup(
        controller: String,
        secret: String,
        group: String,
        url testURL: String,
        timeoutMs: Int = 5000
    ) async -> Bool {
        _ = await proxyGroupDelays(
            controller: controller,
            secret: secret,
            group: group,
            url: testURL,
            timeoutMs: timeoutMs
        )
        return true
    }

    /// Delay map from `GET /proxies/{group}/delay` (empty on failure).
    static func proxyGroupDelays(
        controller: String,
        secret: String,
        group: String,
        url testURL: String,
        timeoutMs: Int = 5000
    ) async -> [String: Int] {
        let encodedGroup = encodePath(group)
        var components = URLComponents(string: "http://\(controller)/proxies/\(encodedGroup)/delay")
        components?.queryItems = [
            URLQueryItem(name: "url", value: testURL),
            URLQueryItem(name: "timeout", value: String(timeoutMs))
        ]
        guard let url = components?.url else { return [:] }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutMs) / 1000.0 + 3)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await localAPISession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            var out: [String: Int] = [:]
            for (k, v) in json {
                if let n = v as? Int { out[k] = n }
                else if let n = v as? NSNumber { out[k] = n.intValue }
            }
            return out
        } catch {
            return [:]
        }
    }

    static func encodePath(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Snapshot of a proxy-group from mihomo `/proxies/{name}`.
    struct ProxyGroupInfo: Equatable, Sendable {
        var name: String
        var type: String
        var now: String
        var all: [String]
    }

    static func fetchProxyGroup(
        controller: String,
        secret: String,
        group: String
    ) async -> ProxyGroupInfo? {
        let encoded = encodePath(group)
        guard let url = URL(string: "http://\(controller)/proxies/\(encoded)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await localAPISession.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let now = json["now"] as? String ?? ""
        let type = json["type"] as? String ?? ""
        let all = (json["all"] as? [String]) ?? []
        return ProxyGroupInfo(name: group, type: type, now: now, all: all)
    }

    static func closeAllConnections(controller: String, secret: String) async {
        guard let url = URL(string: "http://\(controller)/connections") else { return }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "DELETE"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        _ = try? await localAPISession.data(for: request)
    }

    @discardableResult
    static func start(binary: String, configDir: URL) throws -> Process {
        let logURL = configDir.appendingPathComponent("core.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        } else {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }

        // Truncate logs early to keep disk/RAM light.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 256_000 {
            try? Data().write(to: logURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-d", configDir.path]
        process.standardInput = FileHandle.nullDevice

        let outHandle = try FileHandle(forWritingTo: logURL)
        try outHandle.seekToEnd()
        process.standardOutput = outHandle
        process.standardError = outHandle
        process.qualityOfService = .utility

        // Keep pipes from closing if we only hold Process weakly elsewhere.
        process.terminationHandler = { _ in
            try? outHandle.close()
        }

        try process.run()
        try? String(process.processIdentifier).write(to: Paths.pidURL, atomically: true, encoding: .utf8)
        return process
    }
}
