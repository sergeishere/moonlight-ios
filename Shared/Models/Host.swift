import SwiftData
import Foundation

enum PairState: Int {
    case unknown = 0
    case unpaired = 1
    case paired = 2
}

enum HostState: Int {
    case unknown = 0
    case offline = 1
    case online = 2
}

@Model
final class Host {
    // MARK: - Persisted properties

    var uuid: String
    var name: String
    var address: String?
    var externalAddress: String?
    var localAddress: String?
    var ipv6Address: String?
    var mac: String?
    var serverCert: Data?
    var pairState: Int = 0
    var serverCodecModeSupport: Int32 = 0

    @Relationship(deleteRule: .cascade, inverse: \App.host)
    var appList: [App] = []

    @Relationship(deleteRule: .cascade)
    var streamSettings: StreamSettings?

    var httpsPort: UInt16 = 0

    // MARK: - Transient (runtime-only) state

    @Transient var state: Int = 0 // StateUnknown
    @Transient var activeAddress: String?
    @Transient var currentGame: String = "0"
    @Transient var isNvidiaServerSoftware: Bool = false
    @Transient var astrumVersion: Int = 0
    @Transient var updatePending: Bool = false
    @Transient var appVersion: String?
    @Transient var gfeVersion: String?

    // MARK: - Init

    init(
        uuid: String = UUID().uuidString,
        name: String = ""
    ) {
        self.uuid = uuid
        self.name = name
    }

    // MARK: - Computed helpers

    var isPaired: Bool { pairState == PairState.paired.rawValue }
    var isOnline: Bool { state == HostState.online.rawValue }
    var isStatusUnknown: Bool { state == HostState.unknown.rawValue }
    var isAstrumServer: Bool { astrumVersion >= 1 }

    var bestAddress: String? {
        activeAddress ?? localAddress ?? externalAddress ?? address ?? ipv6Address
    }

    // MARK: - Populate from ServerInfo (Swift networking)

    func updateFromServerInfo(_ info: ServerInfo) {
        name = info.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        uuid = info.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        mac = info.mac.trimmingCharacters(in: .whitespacesAndNewlines)

        let httpsPortValue = info.resolvedHttpsPort
        httpsPort = httpsPortValue

        // Local address: skip IPv4 loopback (GS IPv6 Forwarder case)
        let lanAddr = info.localIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lanAddr.hasPrefix("127.") {
            let localPort: UInt16
            if let active = activeAddress {
                let (activeAddr, activePort) = AddressUtils.parseAddressAndPort(active)
                if activeAddr == lanAddr {
                    localPort = activePort
                } else if let local = localAddress {
                    localPort = AddressUtils.parseAddressAndPort(local).port
                } else {
                    localPort = 47989
                }
            } else if let local = localAddress {
                localPort = AddressUtils.parseAddressAndPort(local).port
            } else {
                localPort = 47989
            }
            localAddress = AddressUtils.formatAddressPort(address: lanAddr, port: localPort)
        }

        // External address + port (Sunshine extension)
        let externalHttpPort: UInt16
        if let extPort = info.externalPort {
            externalHttpPort = UInt16(extPort)
        } else if let active = activeAddress {
            externalHttpPort = AddressUtils.parseAddressAndPort(active).port
        } else {
            externalHttpPort = 47989
        }

        if let wanAddr = info.externalIP?.trimmingCharacters(in: .whitespacesAndNewlines), !wanAddr.isEmpty {
            externalAddress = AddressUtils.formatAddressPort(address: wanAddr, port: externalHttpPort)
        } else if let existing = externalAddress {
            let (existingAddr, _) = AddressUtils.parseAddressAndPort(existing)
            externalAddress = AddressUtils.formatAddressPort(address: existingAddr, port: externalHttpPort)
        }

        // State handling
        if !info.isServerBusy {
            currentGame = "0"
        } else {
            currentGame = info.currentGame.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        isNvidiaServerSoftware = info.isNvidiaServerSoftware
        astrumVersion = info.astrumVersion ?? 0
        appVersion = info.appVersion
        gfeVersion = info.gfeVersion

        // Pair status: don't downgrade to unpaired if we have a server cert
        // (local proof of successful pairing — server may not report paired over HTTP)
        if info.isPaired {
            pairState = PairState.paired.rawValue
        } else if serverCert == nil {
            pairState = PairState.unpaired.rawValue
        }

        if let codecMode = info.serverCodecModeSupport {
            serverCodecModeSupport = Int32(codecMode)
        }

        state = HostState.online.rawValue
    }
}
