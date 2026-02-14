import SwiftUI
import SwiftData

@Observable
@MainActor
final class HostListViewModel {
    var discoveryService: DiscoveryService
    var pairingService: PairingService
    var connectionService: HostConnectionService

    var errorMessage: String?
    var showError = false
    var selectedHost: Host?
    var apps: [App] = []
    var loadingApps = false

    init() {
        self.discoveryService = DiscoveryService()
        self.pairingService = PairingService()
        self.connectionService = HostConnectionService()

        CryptoManager.generateKeyPairUsingSSL()
    }

    var hosts: [Host] {
        discoveryService.discoveredHosts
    }

    func configure(modelContext: ModelContext) {
        discoveryService.configure(modelContext: modelContext)
    }

    // MARK: - Discovery

    func startDiscovery() {
        discoveryService.startDiscovery()
    }

    func stopDiscovery() {
        discoveryService.stopDiscovery()
    }

    // MARK: - Host management

    func addHost(address: String) async {
        do {
            let host = try await discoveryService.discoverHost(address: address)
            await updateHost(host)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func removeHost(_ host: Host) {
        discoveryService.removeHost(host)
    }

    func wakeHost(_ host: Host) {
        discoveryService.wakeHost(host)
    }

    func updateHost(_ host: Host) async {
        host.updatePending = true
        discoveryService.pauseDiscovery(for: host)
        let success = await connectionService.fetchServerInfo(for: host)
        discoveryService.resumeDiscovery(for: host)
        host.updatePending = false

        if !success {
            print("Failed to update host: \(host.name)")
        }
    }

    // MARK: - Host selection

    func selectHost(_ host: Host) async {
        if host.isPaired {
            selectedHost = host
            Self.lastHostUUID = host.uuid
            await fetchApps(for: host)
        } else {
            await pairHost(host)
            if host.isPaired {
                selectedHost = host
                Self.lastHostUUID = host.uuid
                await fetchApps(for: host)
            }
        }
    }

    func disconnect() {
        selectedHost = nil
        Self.lastHostUUID = nil
        apps = []
    }

    func reconnectLastHost() async {
        guard let uuid = Self.lastHostUUID,
              let host = hosts.first(where: { $0.uuid == uuid && $0.isPaired && $0.isOnline }) else { return }
        selectedHost = host
        await fetchApps(for: host)
    }

    // MARK: - Last host persistence

    @ObservationIgnored
    private static var lastHostUUID: String? {
        get { UserDefaults.standard.string(forKey: "lastConnectedHostUUID") }
        set { UserDefaults.standard.set(newValue, forKey: "lastConnectedHostUUID") }
    }

    func fetchApps(for host: Host) async {
        loadingApps = true
        let appInfos = await connectionService.fetchAppList(for: host)
        var updatedApps: [App] = []
        for info in appInfos.sorted(by: { $0.name < $1.name }) {
            if let existing = host.appList.first(where: { $0.id == info.id }) {
                existing.updateFromAppInfo(info)
                updatedApps.append(existing)
            } else {
                let app = App(host: host)
                app.updateFromAppInfo(info)
                host.appList.append(app)
                updatedApps.append(app)
            }
        }
        apps = updatedApps
        loadingApps = false
    }

    // MARK: - Pairing

    func unpairHost(_ host: Host) {
        host.serverCert = nil
        host.pairState = Int(PairState.unpaired.rawValue)
        if selectedHost?.uuid == host.uuid {
            disconnect()
        }
        discoveryService.saveContext()
    }

    func pairHost(_ host: Host) async {
        discoveryService.stopDiscoveryBlocking()

        do {
            let serverCert = try await pairingService.pair(host: host)
            host.serverCert = serverCert
            host.pairState = Int(PairState.paired.rawValue)
            discoveryService.saveContext()
        } catch PairingError.alreadyPaired {
            // Already paired, just refresh
        } catch PairingError.cancelled {
            // User cancelled, no action needed
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        discoveryService.startDiscovery()
        await updateHost(host)
    }
}
