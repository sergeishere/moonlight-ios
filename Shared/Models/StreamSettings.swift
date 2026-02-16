import SwiftData
import Foundation

@Model
final class StreamSettings {
    var bitrate: Int32 = 10000
    var framerate: Int32 = 60
    var height: Int32 = 720
    var width: Int32 = 1280
    // Packed format: MAKE_AUDIO_CONFIGURATION(channelCount, channelMask) = (mask << 16) | (count << 8) | 0xCA
    // Stereo: MAKE_AUDIO_CONFIGURATION(2, 0x3) = 0x000302CA
    var audioConfig: Int32 = (0x3 << 16) | (2 << 8) | 0xCA
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

    var onscreenControlsLevel: OnScreenControlsSetting {
        get { OnScreenControlsSetting(rawValue: Int(onscreenControls)) ?? .auto }
        set { onscreenControls = Int32(newValue.rawValue) }
    }
}
