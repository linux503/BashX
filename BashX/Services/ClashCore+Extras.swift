import Foundation
import AppKit

extension ClashCore {
    static func reloadConfig(controller: String, secret: String, path: String) async throws {
        guard var components = URLComponents(string: "http://\(controller)/configs") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "force", value: "true")]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Hot-patch running config (e.g. mode: rule/global/direct).
    static func patchConfig(controller: String, secret: String, body: [String: Any]) async throws {
        guard let url = URL(string: "http://\(controller)/configs") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        let (_, response) = try await URLSession(configuration: config).data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Current mihomo outbound mode: rule / global / direct.
    static func fetchMode(controller: String, secret: String) async -> String? {
        guard let url = URL(string: "http://\(controller)/configs") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 3
        guard let (data, response) = try? await URLSession(configuration: config).data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let mode = json["mode"] as? String { return mode.lowercased() }
        return nil
    }

    /// Apply outbound mode and verify it stuck (ClashX / Verge behavior).
    @discardableResult
    static func applyMode(
        controller: String,
        secret: String,
        mode: ProxyMode
    ) async -> Bool {
        do {
            try await patchConfig(
                controller: controller,
                secret: secret,
                body: ["mode": mode.rawValue]
            )
        } catch {
            return false
        }
        if let current = await fetchMode(controller: controller, secret: secret) {
            return current == mode.rawValue
        }
        // API may omit mode on some builds — treat patch success as OK.
        return true
    }

    /// Best-effort: turn TUN off via API so traffic stops even before process exits.
    static func disableTUNViaAPI(controller: String, secret: String) {
        guard let url = URL(string: "http://\(controller)/configs") else { return }
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "tun": ["enable": false]
        ])
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Start core; when `asRoot` is true, prompt for admin (needed for TUN).
    @discardableResult
    static func start(binary: String, configDir: URL, asRoot: Bool) throws -> Process? {
        if asRoot {
            try startElevated(binary: binary, configDir: configDir)
            return nil
        }
        return try start(binary: binary, configDir: configDir)
    }

    /// Refuse to elevate if binary is missing, group/world-writable, wrong owner, or hash mismatch.
    private static func validateElevatedBinary(_ path: String) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: path) else {
            throw NSError(domain: "BashX", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "内核不可执行，无法提权启动"
            ])
        }
        let attrs = try fm.attributesOfItem(atPath: path)
        if let perms = attrs[.posixPermissions] as? NSNumber {
            let mode = perms.uint16Value
            if mode & 0o022 != 0 {
                throw NSError(domain: "BashX", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "内核文件可被其他用户写入，已拒绝以管理员运行"
                ])
            }
        }
        if let owner = attrs[.ownerAccountName] as? String {
            let me = NSUserName()
            if owner != me && owner != "root" {
                throw NSError(domain: "BashX", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "内核所有者异常（\(owner)），已拒绝提权"
                ])
            }
        }
        // Prefer pinned / recorded SHA-256 for Application Support binary.
        let supportBin = Paths.supportDir.appendingPathComponent("mihomo").path
        if (path as NSString).standardizingPath == (supportBin as NSString).standardizingPath {
            // Heal missing hash sidecar when binary matches the pinned release.
            CoreInstaller.recordHashIfPinnedMatch(at: path)
            guard CoreInstaller.verifyInstalledBinary(at: path) else {
                throw NSError(domain: "BashX", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "内核完整性校验失败，请到「设置 → 内核」重新安装后再开 TUN"
                ])
            }
        }
    }

    /// Prefer one-time privileged helper; fall back to legacy per-launch osascript.
    static func startElevated(binary: String, configDir: URL) throws {
        try validateElevatedBinary(binary)

        // One-time helper: password only on first install / repair.
        do {
            try TunPrivilege.startElevated(binary: binary, configDir: configDir)
            return
        } catch let error as TunPrivilege.PrivilegeError {
            switch error {
            case .helperMissingInApp:
                // Dev builds without embedded helper — fall through to legacy.
                break
            case .startFailed(let msg)
                where msg.contains("非法配置目录")
                    || msg.contains("参数不足")
                    || msg.contains("内核完整性")
                    || msg.contains("非法内核路径"):
                // Protocol / helper mismatch — try legacy osascript once before surfacing.
                do {
                    try startElevatedLegacyOsascript(binary: binary, configDir: configDir)
                    return
                } catch {
                    throw error
                }
            case .installCancelled, .installFailed, .startFailed, .notReady:
                throw error
            }
        } catch {
            throw error
        }

        try startElevatedLegacyOsascript(binary: binary, configDir: configDir)
    }

    /// Legacy: every TUN start prompts for admin (kept as fallback).
    private static func startElevatedLegacyOsascript(binary: String, configDir: URL) throws {
        bringAppFrontForPasswordPrompt()

        func shQuote(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        try? FileManager.default.removeItem(at: Paths.stopSignalURL)
        try? FileManager.default.removeItem(at: Paths.supportDir.appendingPathComponent("tun-launch.sh"))

        let shell = """
        pkill -9 -f 'Application Support/BashX/mihomo' 2>/dev/null || true; \
        BIN=\(shQuote(binary)); DIR=\(shQuote(configDir.path)); LOG=\(shQuote(configDir.appendingPathComponent("core.log").path)); PIDF=\(shQuote(Paths.pidURL.path)); STOP=\(shQuote(Paths.stopSignalURL.path)); \
        rm -f "$PIDF" "$STOP" 2>/dev/null || true; \
        "$BIN" -d "$DIR" >>"$LOG" 2>&1 & BPID=$!; echo "$BPID" > "$PIDF"; \
        while kill -0 "$BPID" 2>/dev/null; do \
          if [ -f "$STOP" ]; then kill -TERM "$BPID" 2>/dev/null || true; sleep 0.4; kill -KILL "$BPID" 2>/dev/null || true; rm -f "$STOP" "$PIDF"; exit 0; fi; \
          sleep 0.35; \
        done; rm -f "$PIDF"
        """
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped) >/dev/null 2>&1 & echo $!\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let cancelled = errText.localizedCaseInsensitiveContains("user canceled")
                || errText.localizedCaseInsensitiveContains("user cancelled")
                || errText.contains("-128")
            let message = cancelled
                ? "已取消管理员授权，TUN 未开启"
                : (errText.isEmpty ? "需要管理员权限才能开启 TUN" : "TUN 提权失败：\(errText)")
            throw NSError(
                domain: "BashX",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        if let pidText = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let watcherPid = Int32(pidText) {
            try? String(watcherPid).write(to: Paths.watcherPidURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.watcherPidURL.path)
        }
    }

    /// Activate the app so the admin password sheet is not buried under other windows.
    private static func bringAppFrontForPasswordPrompt() {
        let work = {
            // Menu-bar (accessory) apps often bury the osascript password sheet — briefly promote.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // Restore accessory / dock preference after the sheet so closing it doesn't quit the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                AppActivation.applyPolicy()
                AppActivation.refreshAfterWindowClosed()
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    /// Ask elevated watcher (or soft pkill) to stop — never prompts for password.
    static func requestStopSignal() {
        try? Data().write(to: Paths.stopSignalURL, options: .atomic)
    }

    /// Soft stop — never prompts for admin. Prefer `stopAllAsync` from @MainActor.
    static func stopAll(binaryHint: String?) {
        requestStopSignal()

        if let pidText = try? String(contentsOf: Paths.pidURL, encoding: .utf8),
           let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            try? FileManager.default.removeItem(at: Paths.pidURL)
        }
        if let pidText = try? String(contentsOf: Paths.watcherPidURL, encoding: .utf8),
           let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            try? FileManager.default.removeItem(at: Paths.watcherPidURL)
        }

        let patterns = [
            "Application Support/BashX/mihomo",
            "Application Support/BashX/clash"
        ]
        for pattern in patterns {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-f", pattern]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }

        if let binaryHint, !binaryHint.isEmpty,
           binaryHint.contains("Application Support/BashX") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-f", binaryHint]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    /// Runs `stopAll` off the calling actor (safe from @MainActor).
    static func stopAllAsync(binaryHint: String?) async {
        let hint = binaryHint
        await Task.detached(priority: .userInitiated) {
            stopAll(binaryHint: hint)
        }.value
    }

    /// Wait for mihomo to exit after stop signal (root watcher handles kill).
    /// Do not call from @MainActor — use `stopAllAndWaitAsync`.
    static func stopAllAndWait(binaryHint: String?, timeoutSeconds: Double = 3.0) {
        stopAll(binaryHint: binaryHint)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline, isMihomoAlive() {
            Thread.sleep(forTimeInterval: 0.2)
            requestStopSignal()
        }
        try? FileManager.default.removeItem(at: Paths.stopSignalURL)
    }

    /// Non-blocking wait for use from @MainActor (avoids UI freeze).
    static func stopAllAndWaitAsync(binaryHint: String?, timeoutSeconds: Double = 3.0) async {
        await stopAllAsync(binaryHint: binaryHint)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let alive = await isMihomoAliveAsync()
            guard alive else { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
            requestStopSignal()
        }
        try? FileManager.default.removeItem(at: Paths.stopSignalURL)
    }

    static func isMihomoAlive() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "Application Support/BashX/mihomo"]
        p.standardOutput = Pipe()
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func isMihomoAliveAsync() async -> Bool {
        await Task.detached(priority: .utility) {
            isMihomoAlive()
        }.value
    }

    /// Kill leftover root mihomo. Default: no password (stop signal + soft).
    /// Set `allowAdmin: true` only when starting TUN and ports are stuck by an old root process.
    static func stopAllForce(binaryHint: String?, allowAdmin: Bool = false) {
        stopAllAndWait(binaryHint: binaryHint, timeoutSeconds: 2.5)
        guard isMihomoAlive(), allowAdmin else { return }

        let pidPath = Paths.pidURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let stopPath = Paths.stopSignalURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"pkill -9 -f 'Application Support/BashX/mihomo' || true; rm -f '\(pidPath)' '\(stopPath)'\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

extension Paths {
    static var pidURL: URL { supportDir.appendingPathComponent("core.pid") }
    static var watcherPidURL: URL { supportDir.appendingPathComponent("core.watcher.pid") }
    /// User-writable; root TUN watcher deletes mihomo when this file appears.
    static var stopSignalURL: URL { supportDir.appendingPathComponent("core.stop") }
    /// SHA-256 of the installed mihomo binary (written after verified download).
    static var coreHashURL: URL { supportDir.appendingPathComponent("mihomo.sha256") }
}
