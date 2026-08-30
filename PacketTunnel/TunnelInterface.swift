import Foundation
import NetworkExtension
import Darwin

enum TunnelInterface {
    static func fileDescriptor(packetFlow: NEPacketTunnelFlow) -> Int32? {
        if let fd = scanUtunFD(preferAddress: AppConstants.tunAddress) { return fd }
        if let fd = socketFD(from: packetFlow) { return fd }
        return nil
    }

    static func fdSource(packetFlow: NEPacketTunnelFlow) -> String {
        if scanUtunFD(preferAddress: AppConstants.tunAddress) != nil { return "utun-scan" }
        if socketFD(from: packetFlow) != nil { return "packetFlow-kvc" }
        return "none"
    }

    static func duplicatedFD(_ fd: Int32) -> Int32? {
        let copy = dup(fd)
        return copy >= 0 ? copy : nil
    }

    /// Physical NIC for mihomo dialer. Prefer en0 / pdp_ip0 — never utun.
    /// (Binding en2 caused mass "network is unreachable" on device logs.)
    static func preferredOutboundInterface() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var en0: String?
        var otherEn: String?
        var cellular: String?
        var candidates: [String] = []

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("lo") || name.hasPrefix("awdl")
                || name.hasPrefix("llw") || name.hasPrefix("ap") || name.hasPrefix("ipsec") {
                continue
            }
            guard p.pointee.ifa_addr != nil,
                  p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(
                p.pointee.ifa_addr,
                socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard ok == 0 else { continue }
            let ip = String(cString: host)
            if ip.hasPrefix("198.18.") || ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }

            candidates.append("\(name)=\(ip)")
            if name == "en0" {
                en0 = name
            } else if name.hasPrefix("en") {
                otherEn = otherEn ?? name
            } else if name.hasPrefix("pdp_ip") {
                cellular = cellular ?? name
            }
        }
        let chosen = en0 ?? cellular ?? otherEn
        return chosen
    }

    /// Debug line of candidate interfaces.
    static func outboundInterfaceDebugLine() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "ifaddrs=nil" }
        defer { freeifaddrs(ifaddr) }
        var parts: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard p.pointee.ifa_addr != nil,
                  p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                p.pointee.ifa_addr,
                socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            parts.append("\(name)=\(String(cString: host))")
        }
        return parts.joined(separator: " ")
    }

    private static func socketFD(from flow: NEPacketTunnelFlow) -> Int32? {
        guard let obj = flow as? NSObject else { return nil }
        for path in ["socket.fileDescriptor", "_socket.fileDescriptor"] {
            let raw = obj.value(forKeyPath: path)
            let fd = (raw as? NSNumber)?.int32Value ?? (raw as? Int32) ?? -1
            if fd > 0 { return fd }
        }
        return nil
    }

    static func scanUtunFD(preferAddress: String? = nil) -> Int32? {
        let preferName: String? = preferAddress.flatMap { nameOfInterface(withIPv4: $0) }
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        var best: (fd: Int32, index: Int)?
        var preferred: Int32?
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2, 2, &buf, &len) != 0 { continue }
            let name = String(cString: buf)
            guard name.hasPrefix("utun") else { continue }
            if let preferName, name == preferName { preferred = fd }
            let idx = Int(name.dropFirst(4)) ?? 0
            if best == nil || idx >= best!.index { best = (fd, idx) }
        }
        return preferred ?? best?.fd
    }

    private static func nameOfInterface(withIPv4 address: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = first
        while true {
            let iface = ptr.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    iface.ifa_addr,
                    socklen_t(iface.ifa_addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                ) == 0, String(cString: host) == address {
                    return String(cString: iface.ifa_name)
                }
            }
            guard let next = iface.ifa_next else { break }
            ptr = next
        }
        return nil
    }
}
