import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.bashx.app"
    static let appBundleIdentifier = "com.bashx.app.ios"
    static let tunnelBundleIdentifier = "com.bashx.app.ios.PacketTunnel"

    /// Mihomo REST API inside the Network Extension process.
    static let externalController = "127.0.0.1:19090"
    static let mixedPort = 17890
    /// Mihomo DNS must bind a real local address. 198.18.0.2 is only the NE DNS
    /// target (hijacked into TUN) — binding it fails (BaoLianDeng / Clash Meta iOS).
    static let dnsListen = "127.0.0.1:1053"

    static let tunAddress = "198.18.0.1"
    static let tunSubnetMask = "255.255.0.0"
    static let tunDNS = "198.18.0.2"
    static let tunIPv6Address = "fdfe:dcba:9876::1"
    static let tunIPv6PrefixLength = 126
    static let defaultMTU = 1500
}
