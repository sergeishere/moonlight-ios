import SwiftUI
import SwiftData
import VideoToolbox
import os

private let log = Logger(subsystem: "com.moonlight", category: "HostListVM")

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
    var streamConfig: StreamConfiguration?

    @ObservationIgnored
    private var pairingTask: Task<Void, Never>?
    @ObservationIgnored
    private var boxArtTask: Task<Void, Never>?

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
        // Show cached apps immediately from SwiftData
        let cached = host.appList.sorted(by: { $0.name < $1.name })
        if !cached.isEmpty {
            apps = cached
        } else {
            loadingApps = true
        }

        // Refresh from server in background
        let result = await connectionService.fetchAppList(for: host)
        switch result {
        case .success(let appInfos):
            if !appInfos.isEmpty {
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
            }
        case .authFailure:
            log.error("Auth failure for \(host.name) — marking unpaired")
            host.serverCert = nil
            host.pairState = PairState.unpaired.rawValue
            discoveryService.saveContext()
            selectedHost = nil
            apps = []
        case .error:
            break // keep showing cached apps
        }
        loadingApps = false

        if case .success = result {
            boxArtTask?.cancel()
            boxArtTask = Task { await loadBoxArt(for: apps, host: host) }
        }
    }

    private func loadBoxArt(for apps: [App], host: Host) async {
        let hostUUID = host.uuid
        let client = MoonlightClient(host: host)
        log.info("loadBoxArt: \(apps.count) apps, host=\(hostUUID)")

        // Filter to only apps missing from cache
        var toDownload: [String] = []
        for app in apps {
            if await BoxArtCache.shared.image(hostUUID: hostUUID, appId: app.id) == nil {
                toDownload.append(app.id)
            }
        }
        log.info("loadBoxArt: \(toDownload.count) to download, \(apps.count - toDownload.count) cached")

        // Download sequentially to avoid saturating the server
        for appId in toDownload {
            guard !Task.isCancelled else {
                log.debug("loadBoxArt: cancelled")
                return
            }
            do {
                let data = try await client.getAppAsset(appId: appId)
                log.info("[\(appId)] downloaded \(data.count) bytes")
                if data.count < 1000 {
                    let preview = String(data: data, encoding: .utf8) ?? "(binary)"
                    log.warning("[\(appId)] response body: \(preview)")
                }
                await BoxArtCache.shared.store(data, hostUUID: hostUUID, appId: appId)
            } catch {
                log.error("[\(appId)] download failed: \(error.localizedDescription)")
            }
        }
        log.info("loadBoxArt: done")
    }

    // MARK: - Streaming

    func launchApp(_ app: App, host: Host, settings: StreamSettings) {
        boxArtTask?.cancel()

        let config = StreamConfiguration()
        config.host = host.bestAddress
        config.httpsPort = host.httpsPort
        config.appID = app.id
        config.appName = app.name
        config.width = settings.width
        config.height = settings.height
        config.frameRate = settings.framerate
        config.bitRate = settings.bitrate
        config.audioConfiguration = settings.audioConfig
        config.optimizeGameSettings = settings.optimizeGames
        config.multiController = settings.multiController
        config.swapABXYButtons = settings.swapABXYButtons
        config.playAudioOnPC = settings.playAudioOnPC
        config.useFramePacing = settings.useFramePacing
        config.absoluteTouchMode = settings.absoluteTouchMode
        config.onscreenControls = settings.onscreenControls
        config.statsOverlay = settings.statsOverlay
        config.serverCert = host.serverCert
        config.serverCodecModeSupport = host.serverCodecModeSupport
        config.appVersion = host.appVersion
        config.gfeVersion = host.gfeVersion
        config.isResume = host.currentGame != "0"

        var supportedVideoFormats: Int32 = 0x0001 // H.264
        let codec = settings.codec
        let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let av1Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        if hevcSupported && (codec == .auto || codec == .hevc) {
            supportedVideoFormats |= 0x0100 // HEVC
            if settings.enableHdr {
                supportedVideoFormats |= 0x0200 // HEVC HDR
            }
        }
        if av1Supported && (codec == .auto || codec == .av1) {
            supportedVideoFormats |= 0x1000 // AV1
            if settings.enableHdr {
                supportedVideoFormats |= 0x2000 // AV1 HDR
            }
        }
        config.supportedVideoFormats = supportedVideoFormats

        print("[StreamConfig] mode=\(config.width)x\(config.height)x\(config.frameRate) bitrate=\(config.bitRate) formats=0x\(String(config.supportedVideoFormats, radix: 16)) host=\(config.host ?? "nil") appID=\(config.appID ?? "nil") sops=\(config.optimizeGameSettings)")

        discoveryService.stopDiscovery()
        streamConfig = config
    }

    func endStream() {
        streamConfig = nil
        discoveryService.startDiscovery()
    }

    // MARK: - Pairing

    func unpairHost(_ host: Host) {
        host.serverCert = nil
        host.pairState = PairState.unpaired.rawValue
        if selectedHost?.uuid == host.uuid {
            disconnect()
        }
        discoveryService.saveContext()
    }

    func pairHost(_ host: Host) async {
        discoveryService.stopDiscoveryBlocking()

        let task = Task {
            do {
                try Task.checkCancellation()
                let serverCert = try await pairingService.pair(host: host)
                host.serverCert = serverCert
                host.pairState = PairState.paired.rawValue
                discoveryService.saveContext()
            } catch is CancellationError {
                // User cancelled via WebView dismiss or task cancellation
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network request cancelled
            } catch PairingError.alreadyPaired {
                // Already paired, just refresh
            } catch PairingError.cancelled {
                // User cancelled, no action needed
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        pairingTask = task
        await task.value
        pairingTask = nil

        discoveryService.startDiscovery()
        await updateHost(host)
    }

    func cancelWebViewPairing() {
        pairingTask?.cancel()
        pairingService.cancelPairing()
    }

}
