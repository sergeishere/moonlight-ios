import SwiftUI
import SwiftData
import VideoToolbox

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
        let appInfos = await connectionService.fetchAppList(for: host)
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
        loadingApps = false

        boxArtTask?.cancel()
        boxArtTask = Task { await loadBoxArt(for: apps, host: host) }
    }

    private func loadBoxArt(for apps: [App], host: Host) async {
        let hostUUID = host.uuid
        let client = MoonlightClient(host: host)

        // Filter to only apps missing from cache
        var toDownload: [String] = []
        for app in apps {
            if await BoxArtCache.shared.image(hostUUID: hostUUID, appId: app.id) == nil {
                toDownload.append(app.id)
            }
        }

        // Download sequentially to avoid saturating the server
        for appId in toDownload {
            guard !Task.isCancelled else { return }
            guard let data = try? await client.getAppAsset(appId: appId) else { continue }
            await BoxArtCache.shared.store(data, hostUUID: hostUUID, appId: appId)
        }
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
        config.audioConfiguration = Self.packedAudioConfig(settings.audioConfig)
        config.optimizeGameSettings = settings.optimizeGames
        config.multiController = settings.multiController
        config.swapABXYButtons = settings.swapABXYButtons
        config.playAudioOnPC = settings.playAudioOnPC
        config.useFramePacing = settings.useFramePacing
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
        host.pairState = Int(PairState.unpaired.rawValue)
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
                host.pairState = Int(PairState.paired.rawValue)
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

    // MARK: - Audio config helpers

    /// Ensures audioConfig is in packed format: (channelMask << 16) | (channelCount << 8) | 0xCA
    /// Handles legacy values that stored raw channel count (2, 6, 8).
    private static func packedAudioConfig(_ value: Int32) -> Int32 {
        // Already packed (has magic byte 0xCA)
        if value & 0xFF == 0xCA { return value }

        // Legacy raw channel count → packed format
        switch value {
        case 2:  return (0x3 << 16)   | (2 << 8) | 0xCA  // stereo
        case 6:  return (0x3F << 16)  | (6 << 8) | 0xCA  // 5.1
        case 8:  return (0x63F << 16) | (8 << 8) | 0xCA  // 7.1
        default: return (0x3 << 16)   | (2 << 8) | 0xCA  // fallback to stereo
        }
    }
}
