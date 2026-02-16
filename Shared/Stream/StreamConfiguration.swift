import Foundation

final class StreamConfiguration {
    var host: String?
    var httpsPort: UInt16 = 0
    var appVersion: String?
    var gfeVersion: String?
    var appID: String?
    var appName: String?
    var rtspSessionUrl: String?
    var serverCodecModeSupport: Int32 = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var frameRate: Int32 = 0
    var bitRate: Int32 = 0
    var riKeyId: Int32 = 0
    var riKey: Data = Data()
    var gamepadMask: Int32 = 0
    var optimizeGameSettings: Bool = false
    var playAudioOnPC: Bool = false
    var swapABXYButtons: Bool = false
    var audioConfiguration: Int32 = 0
    var supportedVideoFormats: Int32 = 0
    var multiController: Bool = false
    var useFramePacing: Bool = false
    var isResume: Bool = false
    var serverCert: Data?
    var absoluteTouchMode: Bool = false
    var onscreenControls: Int32 = 0
    var statsOverlay: Bool = false
}
