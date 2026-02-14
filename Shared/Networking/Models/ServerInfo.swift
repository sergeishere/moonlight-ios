import Foundation

struct ServerInfo: Decodable {
    let hostname: String
    let uniqueId: String
    let mac: String
    let localIP: String
    let state: String
    let pairStatus: Int
    let currentGame: String
    let serverCodecModeSupport: Int?
    let httpsPort: Int?
    let externalIP: String?
    let externalPort: Int?
    let appVersion: String?
    let gfeVersion: String?
    let maxLumaPixelsHEVC: Int?
    let supportedDisplayModes: [DisplayMode]?

    enum CodingKeys: String, CodingKey {
        case hostname, mac, state
        case uniqueId = "uniqueid"
        case localIP = "LocalIP"
        case pairStatus = "PairStatus"
        case currentGame = "currentgame"
        case serverCodecModeSupport = "ServerCodecModeSupport"
        case httpsPort = "HttpsPort"
        case externalIP = "ExternalIP"
        case externalPort = "ExternalPort"
        case appVersion = "appversion"
        case gfeVersion = "GfeVersion"
        case maxLumaPixelsHEVC = "MaxLumaPixelsHEVC"
        case supportedDisplayModes = "SupportedDisplayMode"
    }

    struct DisplayMode: Decodable {
        let width: Int
        let height: Int
        let refreshRate: Int

        enum CodingKeys: String, CodingKey {
            case width = "Width"
            case height = "Height"
            case refreshRate = "RefreshRate"
        }
    }

    // MARK: - Derived properties

    var isServerBusy: Bool {
        state.hasSuffix("_SERVER_BUSY")
    }

    var isNvidiaServerSoftware: Bool {
        state.contains("MJOLNIR")
    }

    var resolvedHttpsPort: UInt16 {
        UInt16(httpsPort ?? 47984)
    }

    var isPaired: Bool {
        pairStatus == 1
    }
}
