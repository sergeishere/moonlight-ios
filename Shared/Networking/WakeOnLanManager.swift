import Foundation

enum WakeOnLanManager {

    // Standard WOL port + Moonlight Internet Hosting Tool port
    private static let staticPorts: [UInt16] = [9, 47009]
    // Ports opened by GFE/Sunshine
    private static let dynamicPorts: [UInt16] = [47998, 47999, 48000, 48002, 48010]

    /// Sends Wake-on-LAN magic packets to all known addresses for the host.
    static func wake(host: Host) {
        guard let mac = host.mac, !mac.isEmpty else { return }
        guard let payload = createPayload(mac: mac) else { return }

        // Collect addresses to try
        var addresses: [(String, UInt16)] = []
        for addr in [host.localAddress, host.externalAddress, host.address, host.ipv6Address] {
            guard let addr else { continue }
            let (raw, port) = AddressUtils.parseAddressAndPort(addr)
            addresses.append((raw, port))
        }
        addresses.append(("255.255.255.255", 47989))

        for (address, basePort) in addresses {
            sendPackets(to: address, basePort: basePort, payload: payload)
        }
    }

    private static func sendPackets(to address: String, basePort: UInt16, payload: Data) {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, nil, &hints, &res) == 0, let addrList = res else {
            return
        }
        defer { freeaddrinfo(addrList) }

        var curr = Optional(addrList)
        while let info = curr {
            let ai = info.pointee

            let sock = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
            guard sock >= 0 else {
                curr = ai.ai_next
                continue
            }
            defer { close(sock) }

            var broadcast: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

            // Static ports
            for port in staticPorts {
                sendTo(sock: sock, payload: payload, addrInfo: ai, port: port)
            }

            // Dynamic ports offset by base port
            for dynPort in dynamicPorts {
                let port = UInt16(Int(dynPort) - 47989 + Int(basePort))
                sendTo(sock: sock, payload: payload, addrInfo: ai, port: port)
            }

            curr = ai.ai_next
        }
    }

    private static func sendTo(sock: Int32, payload: Data, addrInfo: addrinfo, port: UInt16) {
        var storage = sockaddr_storage()
        memcpy(&storage, addrInfo.ai_addr, Int(addrInfo.ai_addrlen))

        let family = storage.ss_family
        withUnsafeMutablePointer(to: &storage) { storagePtr in
            if family == numericCast(AF_INET) {
                storagePtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    sin.pointee.sin_port = port.bigEndian
                }
            } else if family == numericCast(AF_INET6) {
                storagePtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    sin6.pointee.sin6_port = port.bigEndian
                }
            }

            payload.withUnsafeBytes { buf in
                storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    _ = sendto(sock, buf.baseAddress, payload.count, 0, addr, addrInfo.ai_addrlen)
                }
            }
        }
    }

    private static func createPayload(mac: String) -> Data? {
        let macBytes = macStringToBytes(mac)
        guard macBytes.count == 6 else { return nil }

        var payload = Data(capacity: 102)
        // 6 bytes of 0xFF
        payload.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
        // 16 repetitions of MAC address
        for _ in 0..<16 {
            payload.append(macBytes)
        }
        return payload
    }

    private static func macStringToBytes(_ mac: String) -> Data {
        let hex = mac.replacingOccurrences(of: ":", with: "")
        return AddressUtils.hexToBytes(hex)
    }
}
