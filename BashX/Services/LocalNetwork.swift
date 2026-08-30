import Darwin
import Foundation

enum LocalNetwork {
    /// First non-loopback IPv4 (en0/en1 preferred).
    static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifacePtr = ptr {
            let iface = ifacePtr.pointee
            defer { ptr = iface.ifa_next }
            let name = String(cString: iface.ifa_name)
            guard let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if ip.hasPrefix("127.") { continue }
            if name.hasPrefix("en") {
                preferred = preferred ?? ip
            } else if fallback == nil {
                fallback = ip
            }
        }
        return preferred ?? fallback
    }
}
