import Foundation
import Network

actor SpeedTester {
    struct Result: Sendable {
        let name: String
        let delayMs: Int
    }

    func testAll(
        nodes: [ProxyNode],
        timeoutMs: Int,
        concurrency: Int,
        controller: String? = nil,
        secret: String = "",
        testURL: String = "https://www.gstatic.com/generate_204",
        onProgress: @MainActor @escaping (String, Int) -> Void
    ) async -> [Result] {
        let limit = max(1, concurrency)
        var results: [Result] = []
        results.reserveCapacity(nodes.count)
        let useAPI = controller != nil

        await withTaskGroup(of: Result.self) { group in
            var iterator = nodes.makeIterator()

            func enqueueNext() {
                guard let node = iterator.next() else { return }
                group.addTask {
                    let delay: Int
                    if useAPI, let controller {
                        delay = await self.apiDelay(
                            name: node.name,
                            controller: controller,
                            secret: secret,
                            timeoutMs: timeoutMs,
                            testURL: testURL
                        )
                    } else {
                        delay = await self.tcpDelay(host: node.server, port: node.port, timeoutMs: timeoutMs)
                    }
                    return Result(name: node.name, delayMs: delay)
                }
            }

            for _ in 0..<min(limit, nodes.count) {
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

    private func apiDelay(
        name: String,
        controller: String,
        secret: String,
        timeoutMs: Int,
        testURL: String
    ) async -> Int {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        var components = URLComponents()
        components.scheme = "http"
        let hostPort = controller.split(separator: ":", maxSplits: 1).map(String.init)
        components.host = hostPort.first
        if hostPort.count == 2 { components.port = Int(hostPort[1]) }
        components.percentEncodedPath = "/proxies/\(encoded)/delay"
        components.queryItems = [
            URLQueryItem(name: "timeout", value: String(max(timeoutMs, 1000))),
            URLQueryItem(name: "url", value: testURL)
        ]
        guard let url = components.url else { return -1 }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutMs) / 1000.0 + 2.0)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return -1
            }
            return parseDelay(json) ?? -1
        } catch {
            return -1
        }
    }

    private func parseDelay(_ json: [String: Any]) -> Int? {
        if let v = json["delay"] as? Int { return v }
        if let v = json["delay"] as? Double { return Int(v.rounded()) }
        if let v = json["delay"] as? NSNumber { return v.intValue }
        return nil
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
}
