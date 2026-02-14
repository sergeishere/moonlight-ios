import SwiftData
import Foundation

@Model
final class StreamSettings {
    var bitrate: Int32 = 10000
    var framerate: Int32 = 60
    var height: Int32 = 720
    var width: Int32 = 1280
    var audioConfig: Int32 = 2
    var onscreenControls: Int32 = 1
    var preferredCodec: Int = PreferredCodec.auto.rawValue
    var useFramePacing: Bool = false
    var multiController: Bool = true
    var swapABXYButtons: Bool = false
    var playAudioOnPC: Bool = false
    var optimizeGames: Bool = true
    var enableHdr: Bool = false
    var btMouseSupport: Bool = false
    var absoluteTouchMode: Bool = false
    var statsOverlay: Bool = false
    var uniqueId: String = ""

    init() {}

    // MARK: - Convenience accessors

    var codec: PreferredCodec {
        get { PreferredCodec(rawValue: preferredCodec) ?? .auto }
        set { preferredCodec = newValue.rawValue }
    }

    var onscreenControlsLevel: OnScreenControlsLevel {
        get { OnScreenControlsLevel(rawValue: Int(onscreenControls)) ?? .auto }
        set { onscreenControls = Int32(newValue.rawValue) }
    }
}
