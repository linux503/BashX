import Foundation
import NetworkExtension
import Darwin

/// iOS NE: apps only talk to `packetFlow`; mihomo reads/writes a socket pair (not utun fd).
/// Inbound:  readPackets → send(pair, PI+IP) → mihomo/gvisor readv.
/// Outbound: mihomo writev(pair, PI+IP) → recv(pair) → writePackets.
final class PacketFlowBridge {
    private let packetFlow: NEPacketTunnelFlow
    private let bridgeFd: Int32
    private var running = false
    private var outboundThread: Thread?
    private let statsLock = NSLock()

    private var inboundPackets: Int64 = 0
    private var outboundPackets: Int64 = 0
    private var inboundErrors: Int64 = 0
    private var outboundErrors: Int64 = 0
    private var uploadBytes: Int64 = 0
    private var downloadBytes: Int64 = 0

    private static let piIPv4 = UInt32(2).bigEndian   // AF_INET → 00 00 00 02
    private static let piIPv6 = UInt32(30).bigEndian  // AF_INET6 → 00 00 00 1e

    init(packetFlow: NEPacketTunnelFlow, bridgeFd: Int32) {
        self.packetFlow = packetFlow
        self.bridgeFd = bridgeFd
    }

    func start() {
        guard !running else { return }
        running = true
        setNonBlocking(bridgeFd)
        bumpSocketBuffers(bridgeFd)
        readLoop()
        startOutboundThread()
    }

    func stop() {
        running = false
        outboundThread = nil
    }

    func trafficTotals() -> (upload: Int64, download: Int64) {
        statsLock.lock()
        defer { statsLock.unlock() }
        return (uploadBytes, downloadBytes)
    }

    /// Craft a tiny IPv4 UDP DNS query and push it into mihomo via the bridge fd.
    /// This creates packetFlow-visible tunnel activity (unlike 127.0.0.1 API pings).
    func injectDNSKeepalive(to dnsHost: String) {
        guard running, let packet = Self.makeUDPDNSQueryPacket(src: "198.18.0.1", dst: dnsHost) else { return }
        _ = writePacketToBridge(packet, protocolNumber: NSNumber(value: AF_INET))
    }

    private static func makeUDPDNSQueryPacket(src: String, dst: String) -> Data? {
        guard let sip = ipv4(src), let dip = ipv4(dst) else { return nil }
        // DNS query header + QNAME="." + QTYPE A + QCLASS IN
        let dns: [UInt8] = [
            0xB1, 0x42, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x01
        ]
        let udpLen = 8 + dns.count
        var udp = [UInt8](repeating: 0, count: udpLen)
        udp[0] = 0xC0; udp[1] = 0x00 // sport 49152
        udp[2] = 0x00; udp[3] = 53   // dport 53
        udp[4] = UInt8((udpLen >> 8) & 0xff)
        udp[5] = UInt8(udpLen & 0xff)
        // checksum 0 (allowed for IPv4 UDP)
        for i in 0..<dns.count { udp[8 + i] = dns[i] }

        let total = 20 + udpLen
        var ip = [UInt8](repeating: 0, count: total)
        ip[0] = 0x45
        ip[2] = UInt8((total >> 8) & 0xff)
        ip[3] = UInt8(total & 0xff)
        ip[8] = 64 // TTL
        ip[9] = 17 // UDP
        ip[12] = sip.0; ip[13] = sip.1; ip[14] = sip.2; ip[15] = sip.3
        ip[16] = dip.0; ip[17] = dip.1; ip[18] = dip.2; ip[19] = dip.3
        var sum: UInt32 = 0
        for i in stride(from: 0, to: 20, by: 2) {
            sum += UInt32(ip[i]) << 8 | UInt32(ip[i + 1])
        }
        while sum > 0xffff { sum = (sum & 0xffff) + (sum >> 16) }
        let csum = ~UInt16(sum & 0xffff)
        ip[10] = UInt8(csum >> 8)
        ip[11] = UInt8(csum & 0xff)
        for i in 0..<udpLen { ip[20 + i] = udp[i] }
        return Data(ip)
    }

    private static func ipv4(_ s: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let p = s.split(separator: ".").compactMap { UInt8($0) }
        guard p.count == 4 else { return nil }
        return (p[0], p[1], p[2], p[3])
    }

    var statsLine: String {
        statsLock.lock()
        defer { statsLock.unlock() }
        return "bridge in=\(inboundPackets)/\(uploadBytes)B out=\(outboundPackets)/\(downloadBytes)B inErr=\(inboundErrors) outErr=\(outboundErrors)"
    }

    // MARK: - Inbound (apps → mihomo)

    private func readLoop() {
        guard running else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.running else { return }
            for (packet, proto) in zip(packets, protocols) {
                if self.writePacketToBridge(packet, protocolNumber: proto) {
                    self.statsLock.lock()
                    self.inboundPackets &+= 1
                    self.uploadBytes &+= Int64(packet.count)
                    self.statsLock.unlock()
                } else {
                    self.statsLock.lock()
                    self.inboundErrors &+= 1
                    self.statsLock.unlock()
                }
            }
            self.readLoop()
        }
    }

    @discardableResult
    private func writePacketToBridge(_ packet: Data, protocolNumber: NSNumber) -> Bool {
        guard !packet.isEmpty else { return false }
        var frame = Data(count: 4 + packet.count)
        var proto = Self.piProtocol(for: packet, fallback: protocolNumber)
        withUnsafeBytes(of: &proto) { pi in
            frame.replaceSubrange(0..<4, with: pi)
        }
        frame.replaceSubrange(4..<(4 + packet.count), with: packet)

        return frame.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            for _ in 0..<64 {
                let n = send(bridgeFd, base, frame.count, 0)
                if n == frame.count { return true }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS) {
                    usleep(200)
                    continue
                }
                return false
            }
            return false
        }
    }

    // MARK: - Outbound (mihomo → apps)

    private func startOutboundThread() {
        let thread = Thread { [weak self] in
            self?.outboundLoop()
        }
        thread.name = "bashx.tunnel.outbound"
        thread.qualityOfService = .userInitiated
        outboundThread = thread
        thread.start()
    }

    private func outboundLoop() {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while running {
            let n = recv(bridgeFd, &buffer, buffer.count, 0)
            if n <= 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1_000)
                    continue
                }
                if running {
                    statsLock.lock()
                    outboundErrors &+= 1
                    statsLock.unlock()
                    usleep(2_000)
                    continue
                }
                break
            }
            guard n > 4 else { continue }
            let packet = Data(buffer[4..<n])
            let proto = Self.protocolNumber(for: packet)
            packetFlow.writePackets([packet], withProtocols: [proto])
            statsLock.lock()
            outboundPackets &+= 1
            downloadBytes &+= Int64(packet.count)
            statsLock.unlock()
        }
    }

    // MARK: - Helpers

    private static func piProtocol(for packet: Data, fallback: NSNumber) -> UInt32 {
        if let first = packet.first {
            return (first >> 4) == 6 ? piIPv6 : piIPv4
        }
        return fallback.int32Value == AF_INET6 ? piIPv6 : piIPv4
    }

    private static func protocolNumber(for packet: Data) -> NSNumber {
        guard let first = packet.first else { return NSNumber(value: AF_INET) }
        return NSNumber(value: (first >> 4) == 6 ? AF_INET6 : AF_INET)
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    private func bumpSocketBuffers(_ fd: Int32) {
        // 96KB — Douyin video + 256KB×4 blew NE jetsam (~50MB) → On-Demand reconnect storm.
        var size: Int32 = 96 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
    }
}

enum TunnelSocketPair {
    struct Pair {
        let mihomoFd: Int32
        let bridgeFd: Int32
    }

    static func make() -> Pair? {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else { return nil }
        var size: Int32 = 96 * 1024
        for fd in fds {
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        }
        return Pair(mihomoFd: fds[0], bridgeFd: fds[1])
    }
}
