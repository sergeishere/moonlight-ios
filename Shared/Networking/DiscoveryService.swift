import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.moonlight-stream", category: "Discovery")

@Observable
@MainActor
final class DiscoveryService {
    var discoveredHosts: [Host] = []

    private var modelContext: ModelContext?
    private var bonjourBrowser: BonjourBrowser?
    private var pollers: [String: HostPoller] = [:] // keyed by host UUID
    private var pausedHostUUIDs: Set<String> = []
    private var browseTask: Task<Void, Never>?
    private var isDiscovering = false

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext

        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "?"
        log.info("Data directory: \(docsPath)")

        loadSavedHosts()
    }

    // MARK: - Discovery control

    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true

        log.info("Starting discovery, \(self.discoveredHosts.count) saved hosts")

        // Start Bonjour browser — primary LAN discovery
        let browser = BonjourBrowser()
        self.bonjourBrowser = browser
        browser.start()

        browseTask = Task { [weak self] in
            for await endpoint in browser.endpoints {
                guard let self, !Task.isCancelled else { break }
                log.info("Bonjour: found '\(endpoint.name)' at \(endpoint.localAddress ?? "nil")")
                await self.handleDiscoveredEndpoint(endpoint)
            }
        }

        // If client is NOT on a LAN, Bonjour won't find LAN hosts — try WAN poll
        if !Self.isClientOnLAN() {
            log.info("Client is not on LAN — polling saved hosts via WAN")
            for host in discoveredHosts where !pausedHostUUIDs.contains(host.uuid) {
                pollWANOnce(for: host)
            }
        } else {
            log.info("Client is on LAN — relying on Bonjour for discovery")
        }
    }

    func stopDiscovery() {
        guard isDiscovering else { return }
        isDiscovering = false

        bonjourBrowser?.stop()
        bonjourBrowser = nil
        browseTask?.cancel()
        browseTask = nil

        for (_, poller) in pollers {
            Task { await poller.stopPolling() }
        }
        pollers.removeAll()
    }

    func stopDiscoveryBlocking() {
        stopDiscovery()
    }

    // MARK: - Host management

    func discoverHost(address: String) async throws -> Host {
        let (serverInfo, activeAddress) = try await HostPoller.discoverOnce(address: address)

        let host = findOrCreateHost(uuid: serverInfo.uniqueId, name: serverInfo.hostname)
        host.updateFromServerInfo(serverInfo)
        host.activeAddress = activeAddress
        host.address = address

        // STUN for external address
        if !AddressUtils.isVPNActive() {
            let (addr, _) = AddressUtils.parseAddressAndPort(address)
            if let addrCStr = addr.cString(using: .utf8) {
                let rawAddr = inet_addr(addrCStr)
                if AddressUtils.isLANAddress(rawAddr) {
                    var wanAddr = in_addr()
                    let err = LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &wanAddr.s_addr)
                    if err == 0 {
                        var addrStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        inet_ntop(AF_INET, &wanAddr, &addrStr, socklen_t(INET_ADDRSTRLEN))
                        host.externalAddress = String(cString: addrStr)
                    }
                }
            }
        }

        saveContext()

        if isDiscovering {
            startPoller(for: host)
        }

        return host
    }

    func removeHost(_ host: Host) {
        stopPoller(for: host)
        modelContext?.delete(host)
        discoveredHosts.removeAll { $0.uuid == host.uuid }
        saveContext()
    }

    func wakeHost(_ host: Host) {
        WakeOnLanManager.wake(host: host)
    }

    func pauseDiscovery(for host: Host) {
        pausedHostUUIDs.insert(host.uuid)
        stopPoller(for: host)
    }

    func resumeDiscovery(for host: Host) {
        pausedHostUUIDs.remove(host.uuid)
        if isDiscovering {
            startPoller(for: host)
        }
    }

    // MARK: - Bonjour handling

    private func handleDiscoveredEndpoint(_ endpoint: BonjourBrowser.DiscoveredEndpoint) async {
        guard let address = endpoint.localAddress else { return }

        // If we already know this host, use its HTTPS port and cert for proper pair status
        let existingHost = discoveredHosts.first { $0.name == endpoint.name }
        let (addr, port) = AddressUtils.parseAddressAndPort(address)
        let client = MoonlightClient(
            address: addr,
            port: port,
            httpsPort: existingHost?.httpsPort ?? 0,
            serverCert: existingHost?.serverCert
        )

        do {
            let serverInfo = try await client.getServerInfo(timeout: MoonlightClient.normalTimeout)
            let host = findOrCreateHost(uuid: serverInfo.uniqueId, name: serverInfo.hostname)
            host.updateFromServerInfo(serverInfo)
            host.activeAddress = address

            if let local = endpoint.localAddress {
                host.localAddress = local
            }
            if let ipv6 = endpoint.ipv6Address {
                host.ipv6Address = ipv6
            }
            if let ext = endpoint.externalAddress {
                host.externalAddress = ext
            }

            saveContext()

            // Host is reachable — start state maintenance poller
            if isDiscovering && !pausedHostUUIDs.contains(host.uuid) {
                startPoller(for: host)
            }
        } catch {
            log.warning("Bonjour endpoint '\(endpoint.name)' unreachable: \(error.localizedDescription)")
        }
    }

    // MARK: - Polling

    /// Single WAN poll for saved hosts that have external addresses.
    /// LAN hosts are discovered by Bonjour, no need to poll.
    private func pollWANOnce(for host: Host) {
        guard let wanAddress = host.externalAddress ?? host.address else { return }
        let serverCert = host.serverCert
        let hostUUID = host.uuid
        let hostName = host.name

        log.info("WAN poll for '\(hostName)' at \(wanAddress)")

        Task {
            let (addr, port) = AddressUtils.parseAddressAndPort(wanAddress)
            let client = MoonlightClient(
                address: addr,
                port: port,
                httpsPort: 0,
                serverCert: serverCert
            )

            do {
                let serverInfo = try await client.getServerInfo(timeout: MoonlightClient.wanTimeout)
                guard let host = self.discoveredHosts.first(where: { $0.uuid == hostUUID }) else { return }
                host.updateFromServerInfo(serverInfo)
                host.activeAddress = wanAddress
                log.info("WAN poll for '\(hostName)' OK")
                self.saveContext()

                if self.isDiscovering && !self.pausedHostUUIDs.contains(hostUUID) {
                    self.startPoller(for: host)
                }
            } catch {
                log.info("WAN poll for '\(hostName)' failed: \(error.localizedDescription)")
            }
        }
    }

    /// Checks if the client device has a LAN IP (WiFi/Ethernet with private address).
    /// If true, Bonjour can discover LAN hosts and WAN polling is unnecessary.
    private static func isClientOnLAN() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            defer { current = addr.pointee.ifa_next }

            let flags = Int32(addr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let ip = addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            if AddressUtils.isLANAddress(ip) {
                return true
            }
        }
        return false
    }

    /// Starts continuous poller for a host confirmed to be reachable.
    private func startPoller(for host: Host) {
        guard pollers[host.uuid] == nil else { return }

        let poller = HostPoller()
        pollers[host.uuid] = poller

        let addresses = getAddressList(for: host)
        let httpsPort = host.httpsPort
        let serverCert = host.serverCert
        let hostUUID = host.uuid
        let hostName = host.name

        log.info("Starting poller for '\(hostName)' addresses=\(addresses)")

        Task {
            await poller.startPolling(
                addresses: addresses,
                httpsPort: httpsPort,
                serverCert: serverCert,
                onResult: { [weak self] result in
                    guard let self else { return }
                    guard let host = self.discoveredHosts.first(where: { $0.uuid == hostUUID }) else { return }
                    let oldState = host.state
                    host.updateFromServerInfo(result.serverInfo)
                    host.activeAddress = result.activeAddress
                    if oldState != host.state {
                        log.info("Host '\(hostName)' state: \(oldState) -> \(host.state) via \(result.activeAddress)")
                    }
                    self.saveContext()
                },
                onStoppedByFailures: { [weak self] in
                    guard let self else { return }
                    log.info("Poller for '\(hostName)' stopped — host went offline")
                    self.pollers.removeValue(forKey: hostUUID)
                    if let host = self.discoveredHosts.first(where: { $0.uuid == hostUUID }) {
                        host.state = Int(HostState.offline.rawValue)
                    }
                }
            )
        }
    }

    private func stopPoller(for host: Host) {
        if let poller = pollers.removeValue(forKey: host.uuid) {
            Task { await poller.stopPolling() }
        }
    }

    private func getAddressList(for host: Host) -> [String] {
        var addresses: [String] = []
        if let addr = host.localAddress { addresses.append(addr) }
        if let addr = host.address { addresses.append(addr) }
        if let addr = host.externalAddress { addresses.append(addr) }
        if let addr = host.ipv6Address { addresses.append(addr) }

        // Deduplicate preserving order
        var seen = Set<String>()
        return addresses.filter { seen.insert($0).inserted }
    }

    // MARK: - Persistence

    private func loadSavedHosts() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Host>()
        do {
            let allHosts = try modelContext.fetch(descriptor)

            // Deduplicate by UUID
            var seenUUIDs = Set<String>()
            var uniqueHosts: [Host] = []
            for host in allHosts {
                if seenUUIDs.contains(host.uuid) {
                    modelContext.delete(host)
                } else {
                    seenUUIDs.insert(host.uuid)
                    uniqueHosts.append(host)
                }
            }

            // Deduplicate by name
            var seenNames = Set<String>()
            var deduplicatedHosts: [Host] = []
            for host in uniqueHosts {
                if seenNames.contains(host.name) {
                    modelContext.delete(host)
                } else {
                    seenNames.insert(host.name)
                    deduplicatedHosts.append(host)
                }
            }

            discoveredHosts = deduplicatedHosts

            // Fix pairState for hosts that have a server cert but lost their pair status
            var needsSave = false
            for host in discoveredHosts where host.serverCert != nil && !host.isPaired {
                host.pairState = Int(PairState.paired.rawValue)
                log.info("Fixed pairState for '\(host.name)' (had cert but was not marked paired)")
                needsSave = true
            }
            if needsSave { saveContext() }

            // Saved hosts start as offline — Bonjour will update them to online
            for host in discoveredHosts {
                host.state = Int(HostState.offline.rawValue)
                host.activeAddress = host.bestAddress
            }

            for host in discoveredHosts {
                log.info("""
                    Loaded host '\(host.name)' uuid=\(host.uuid) \
                    paired=\(host.isPaired) \
                    local=\(host.localAddress ?? "nil") \
                    addr=\(host.address ?? "nil") \
                    ext=\(host.externalAddress ?? "nil") \
                    active=\(host.activeAddress ?? "nil") \
                    cert=\(host.serverCert.map { "\($0.count)B" } ?? "nil")
                    """)
            }

            if allHosts.count != deduplicatedHosts.count {
                saveContext()
            }
        } catch {
            print("Failed to load saved hosts: \(error)")
        }
    }

    private func findOrCreateHost(uuid: String, name: String) -> Host {
        if let existing = discoveredHosts.first(where: { $0.uuid == uuid }) {
            return existing
        }
        if let existing = discoveredHosts.first(where: { $0.name == name }) {
            return existing
        }

        let host = Host(uuid: uuid, name: name)
        modelContext?.insert(host)
        discoveredHosts.append(host)
        return host
    }

    func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}

enum DiscoveryError: LocalizedError {
    case connectionFailed(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message): message
        case .unknown: "Unknown discovery error"
        }
    }
}
