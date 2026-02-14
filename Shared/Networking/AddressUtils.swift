import Foundation

enum AddressUtils {

    // MARK: - Address:Port Parsing

    /// Parses "address:port" or "[ipv6]:port" format.
    /// Returns (address, port). Port defaults to 47989 if not specified.
    static func parseAddressAndPort(_ addressPort: String) -> (address: String, port: UInt16) {
        // IPv6 with brackets: [::1]:47989
        if let openBracket = addressPort.firstIndex(of: "["),
           let closeBracket = addressPort.firstIndex(of: "]") {
            let address = String(addressPort[addressPort.index(after: openBracket)..<closeBracket])
            let afterBracket = addressPort.index(after: closeBracket)
            if afterBracket < addressPort.endIndex,
               addressPort[afterBracket] == ":",
               let port = UInt16(addressPort[addressPort.index(after: afterBracket)...]) {
                return (address, port)
            }
            return (address, 47989)
        }

        // IPv4: check for single colon (not IPv6 double-colon)
        let components = addressPort.split(separator: ":", maxSplits: 2)
        if components.count == 2, !addressPort.contains("::") {
            let address = String(components[0])
            let port = UInt16(components[1]) ?? 47989
            return (address, port)
        }

        return (addressPort, 47989)
    }

    /// Formats address and port into "address:port" or "[ipv6]:port".
    static func formatAddressPort(address: String, port: UInt16) -> String {
        if address.contains(":") {
            return "[\(address)]:\(port)"
        }
        return "\(address):\(port)"
    }

    /// Makes address URL-safe: wraps IPv6 in brackets.
    static func urlSafeAddress(_ address: String) -> String {
        if address.contains(":") {
            return "[\(address)]"
        }
        return address
    }

    // MARK: - LAN Detection

    /// Checks if an IPv4 address (in network byte order) is on a local network.
    static func isLANAddress(_ addr: in_addr_t) -> Bool {
        let hostAddr = addr.bigEndian // Convert to host byte order

        // 10.0.0.0/8
        if (hostAddr & 0xFF00_0000) == 0x0A00_0000 { return true }
        // 172.16.0.0/12
        if (hostAddr & 0xFFF0_0000) == 0xAC10_0000 { return true }
        // 192.168.0.0/16
        if (hostAddr & 0xFFFF_0000) == 0xC0A8_0000 { return true }
        // 169.254.0.0/16 (link-local)
        if (hostAddr & 0xFFFF_0000) == 0xA9FE_0000 { return true }

        return false
    }

    /// Checks if an address string (IPv4/IPv6 or "address:port") is on a local network.
    static func isLANAddress(_ address: String) -> Bool {
        let (addr, _) = parseAddressAndPort(address)

        // IPv6: check ULA (fd00::/8) and link-local (fe80::/10)
        if addr.contains(":") {
            let lower = addr.lowercased()
            return lower.hasPrefix("fd") || lower.hasPrefix("fe80")
        }

        guard let cStr = addr.cString(using: .utf8) else { return false }
        let rawAddr = inet_addr(cStr)
        guard rawAddr != INADDR_NONE else { return false }
        return isLANAddress(rawAddr)
    }

    // MARK: - VPN Detection

    /// Checks if the active network interface appears to be a VPN.
    static func isVPNActive() -> Bool {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = proxySettings["__SCOPED__"] as? [String: Any] else {
            return false
        }

        let vpnKeywords = ["tap", "tun", "ppp", "ipsec"]
        return scoped.keys.contains { key in
            vpnKeywords.contains { key.contains($0) }
        }
    }

    // MARK: - Hex Conversion

    static func bytesToHex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    static func hexToBytes(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
}
