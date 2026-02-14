import Foundation
import Network
import os

private let log = Logger(subsystem: "com.moonlight-stream", category: "Bonjour")

final class BonjourBrowser: Sendable {

    struct DiscoveredEndpoint: Sendable {
        let name: String
        let localAddress: String?
        let ipv6Address: String?
        let externalAddress: String?
    }

    private let browser: NWBrowser
    private let stateStream: AsyncStream<NWBrowser.State>
    private let stateContinuation: AsyncStream<NWBrowser.State>.Continuation
    private let resultsStream: AsyncStream<DiscoveredEndpoint>
    private let resultsContinuation: AsyncStream<DiscoveredEndpoint>.Continuation

    var endpoints: AsyncStream<DiscoveredEndpoint> { resultsStream }

    init() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_nvstream._tcp", domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        self.browser = NWBrowser(for: descriptor, using: parameters)

        (stateStream, stateContinuation) = AsyncStream<NWBrowser.State>.makeStream()
        (resultsStream, resultsContinuation) = AsyncStream<DiscoveredEndpoint>.makeStream()

        browser.stateUpdateHandler = { [stateContinuation] state in
            log.info("Browser state: \(String(describing: state))")
            stateContinuation.yield(state)
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            log.info("Browse results changed: \(results.count) total, \(changes.count) changes")
            for change in changes {
                switch change {
                case .added(let result):
                    log.info("Service added: \(String(describing: result.endpoint))")
                    self.resolveEndpoint(result)
                case .removed(let result):
                    log.info("Service removed: \(String(describing: result.endpoint))")
                default:
                    break
                }
            }
        }
    }

    func start() {
        browser.start(queue: .global(qos: .utility))
    }

    func stop() {
        browser.cancel()
        resultsContinuation.finish()
        stateContinuation.finish()
    }

    private func resolveEndpoint(_ result: NWBrowser.Result) {
        let name: String
        if case .service(let serviceName, _, _, _) = result.endpoint {
            name = serviceName
        } else {
            return
        }

        // Resolve the endpoint by creating a temporary connection
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, name] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let discovered = self.buildEndpoint(from: connection, name: name) {
                    log.info("Resolved '\(name)' -> \(discovered.localAddress ?? "nil")")
                    self.resultsContinuation.yield(discovered)
                } else {
                    log.warning("Failed to build endpoint for '\(name)'")
                }
                connection.cancel()
            case .failed(let error):
                log.warning("Connection to '\(name)' failed: \(error)")
                connection.cancel()
            case .waiting(let error):
                log.debug("Connection to '\(name)' waiting: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))

        // Timeout after 5 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if connection.state != .cancelled {
                connection.cancel()
            }
        }
    }

    private func buildEndpoint(from connection: NWConnection, name: String) -> DiscoveredEndpoint? {
        guard let path = connection.currentPath,
              let endpoint = path.remoteEndpoint,
              case .hostPort(let host, let port) = endpoint else {
            return nil
        }

        let address = Self.addressString(from: host)
        let formattedAddress = AddressUtils.formatAddressPort(
            address: address,
            port: port.rawValue
        )

        let externalAddr = Self.resolveExternalAddress(for: host)

        return DiscoveredEndpoint(
            name: name,
            localAddress: formattedAddress,
            ipv6Address: nil,
            externalAddress: externalAddr
        )
    }

    /// Extracts the IP address string, stripping the zone ID (e.g. "%en0") that NWConnection appends.
    private static func addressString(from host: NWEndpoint.Host) -> String {
        let raw: String
        switch host {
        case .ipv4(let ipv4):
            raw = "\(ipv4)"
        case .ipv6(let ipv6):
            raw = "\(ipv6)"
        case .name(let hostname, _):
            return hostname
        @unknown default:
            raw = "\(host)"
        }
        // Strip zone ID suffix like "%en0", "%awdl0"
        if let percentIndex = raw.firstIndex(of: "%") {
            return String(raw[raw.startIndex..<percentIndex])
        }
        return raw
    }

    private static func resolveExternalAddress(for host: NWEndpoint.Host) -> String? {
        guard !AddressUtils.isVPNActive(),
              case .ipv4(let ipv4) = host else {
            return nil
        }

        var addrBytes = ipv4
        let rawAddr = withUnsafePointer(to: &addrBytes) {
            $0.withMemoryRebound(to: in_addr_t.self, capacity: 1) { $0.pointee }
        }

        guard AddressUtils.isLANAddress(rawAddr) else { return nil }

        var wanAddr = in_addr()
        let err = LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &wanAddr.s_addr)
        guard err == 0 else { return nil }

        var addrStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &wanAddr, &addrStr, socklen_t(INET_ADDRSTRLEN))
        return String(cString: addrStr)
    }
}
