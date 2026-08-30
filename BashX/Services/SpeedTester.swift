import Foundation
import Network

actor SpeedTester {
    struct Result: Sendable {
        let name: String
        let delayMs: Int
    }

    /// Live proxy names from mihomo `/proxies` — used when UI name differs slightly from runtime.
    private var proxyCatalog: [String: String] = [:]
    private var catalogDelays: [String: Int] = [:]
    private var catalogController = ""

    func testAll(
        nodes: [ProxyNode],
        timeoutMs: Int,
        concurrency: Int,
        controller: String? = nil,
        secret: String = "",
        testURL: String = "https://www.gstatic.com/generate_204",
        onProgress: @MainActor @escaping (String, Int) -> Void
    ) async -> [Result] {
        let testables = nodes.filter { ClashConfigParser.isSpeedTestable($0) }
        guard !testables.isEmpty else { return [] }

        let limit = max(1, min(concurrency, 16))
        let apiTimeout = max(timeoutMs, 5000)
        let useAPI = controller != nil
        if useAPI, let controller {
            await refreshProxyCatalog(controller: controller, secret: secret)
        }

        var results: [Result] = []
        results.reserveCapacity(testables.count)

        await withTaskGroup(of: Result.self) { group in
            var iterator = testables.makeIterator()

            func enqueueNext() {
                guard let node = iterator.next() else { return }
                group.addTask {
                    let delay: Int
                    if useAPI, let controller {
                        delay = await self.apiDelay(
                            node: node,
                            controller: controller,
                            secret: secret,
                            timeoutMs: apiTimeout,
                            testURL: testURL
                        )
                    } else {
                        delay = await self.tcpDelay(host: node.server, port: node.port, timeoutMs: apiTimeout)
                    }
                    return Result(name: node.name, delayMs: delay)
                }
            }

            for _ in 0..<min(limit, testables.count) {
                enqueueNext()
            }

            for await result in group {
                results.append(result)
                await onProgress(result.name, result.delayMs)
                enqueueNext()
            }
        }

        return results
    }

    private func refreshProxyCatalog(controller: String, secret: String) async {
        if catalogController == controller, !proxyCatalog.isEmpty { return }
        catalogController = controller
        proxyCatalog.removeAll(keepingCapacity: true)
        catalogDelays.removeAll(keepingCapacity: true)

        guard let url = URL(string: "http://\(controller)/proxies") else { return }
        var request = URLRequest(url: url, timeoutInterval: 4)
        applyAuth(&request, secret: secret)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        guard let (data, response) = try? await URLSession(configuration: config).data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = json["proxies"] as? [String: Any] else { return }

        for (name, value) in proxies {
            guard let dict = value as? [String: Any] else { continue }
            let type = (dict["type"] as? String)?.lowercased() ?? ""
            if ["direct", "reject", "select", "url-test", "fallback", "load-balance", "relay", "pass", "compatible"].contains(type) {
                continue
            }
            proxyCatalog[name] = name
            if let history = dict["history"] as? [[String: Any]] {
                for entry in history.reversed() {
                    if let ms = intValue(entry["delay"]), ms > 0 {
                        catalogDelays[name] = ms
                        break
                    }
                }
            }
            if let server = dict["server"] as? String, let port = intValue(dict["port"]) {
                let key = "\(server.lowercased()):\(port)"
                proxyCatalog[key] = name
            }
        }
    }

    private func resolveProxyName(_ node: ProxyNode) -> String {
        if proxyCatalog[node.name] != nil { return node.name }
        let key = "\(node.server.lowercased()):\(node.port)"
        if let resolved = proxyCatalog[key] { return resolved }
        return node.name
    }

    private func apiDelay(
        node: ProxyNode,
        controller: String,
        secret: String,
        timeoutMs: Int,
        testURL: String
    ) async -> Int {
        let proxyName = resolveProxyName(node)
        let urls = testURLCandidates(primary: testURL)
        for url in urls {
            if let ms = await apiDelayOnce(
                proxyName: proxyName,
                controller: controller,
                secret: secret,
                timeoutMs: timeoutMs,
                testURL: url
            ), ms > 0 {
                return ms
            }
        }
        if let cached = catalogDelays[proxyName], cached > 0 { return cached }
        if let cached = catalogDelays[node.name], cached > 0 { return cached }
        let key = "\(node.server.lowercased()):\(node.port)"
        if let resolved = proxyCatalog[key], let cached = catalogDelays[resolved], cached > 0 {
            return cached
        }
        return -1
    }

    private func testURLCandidates(primary: String) -> [String] {
        var list: [String] = []
        func add(_ u: String) {
            let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !list.contains(t) else { return }
            list.append(t)
        }
        add(primary)
        add("https://www.gstatic.com/generate_204")
        add("http://www.msftconnecttest.com/connecttest.txt")
        add("https://cp.cloudflare.com/")
        return list
    }

    private func apiDelayOnce(
        proxyName: String,
        controller: String,
        secret: String,
        timeoutMs: Int,
        testURL: String
    ) async -> Int? {
        let encoded = Self.encodePath(proxyName)
        var components = URLComponents(string: "http://\(controller)/proxies/\(encoded)/delay")
        components?.queryItems = [
            URLQueryItem(name: "timeout", value: String(max(timeoutMs, 3000))),
            URLQueryItem(name: "url", value: testURL),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutMs) / 1000.0 + 4.0)
        request.httpMethod = "GET"
        applyAuth(&request, secret: secret)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = TimeInterval(timeoutMs) / 1000.0 + 4
        config.connectionProxyDictionary = [:]

        do {
            let (data, response) = try await URLSession(configuration: config).data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let message = json["message"] as? String, !message.isEmpty, json["delay"] == nil {
                return nil
            }
            return parseDelay(json)
        } catch {
            return nil
        }
    }

    private func parseDelay(_ json: [String: Any]) -> Int? {
        let raw: Int? = {
            if let v = json["delay"] as? Int { return v }
            if let v = json["delay"] as? Double { return Int(v.rounded()) }
            if let v = json["delay"] as? NSNumber { return v.intValue }
            return nil
        }()
        guard let raw, raw > 0, raw < 60_000 else { return nil }
        return raw
    }

    private func tcpDelay(host: String, port: Int, timeoutMs: Int) async -> Int {
        guard !host.isEmpty, port > 0, port <= 65535 else { return -1 }

        let start = Date()
        let connected = await connect(host: host, port: UInt16(port), timeoutMs: timeoutMs)
        guard connected else { return -1 }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return max(ms, 1)
    }

    private func connect(host: String, port: UInt16, timeoutMs: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "bashx.speedtest")
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )

            let lock = NSLock()
            var resumed = false
            func finish(_ ok: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: ok)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                finish(false)
            }
        }
    }

    private func applyAuth(_ req: inout URLRequest, secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func encodePath(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func intValue(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? String { return Int(v) }
        return nil
    }
}
