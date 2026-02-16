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

    // Per-host settings support
    var isGlobalDefaults: Bool = false
    var screenCurvature: Int = 1 // ScreenCurvature.gentle

    @Relationship(inverse: \Host.streamSettings)
    var host: Host?

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

    var curvature: ScreenCurvature {
        get { ScreenCurvature(rawValue: screenCurvature) ?? .gentle }
        set { screenCurvature = newValue.rawValue }
    }

    // MARK: - Copy

    static func makeCopy(from source: StreamSettings) -> StreamSettings {
        let copy = StreamSettings()
        copy.bitrate = source.bitrate
        copy.framerate = source.framerate
        copy.height = source.height
        copy.width = source.width
        copy.audioConfig = source.audioConfig
        copy.onscreenControls = source.onscreenControls
        copy.preferredCodec = source.preferredCodec
        copy.useFramePacing = source.useFramePacing
        copy.multiController = source.multiController
        copy.swapABXYButtons = source.swapABXYButtons
        copy.playAudioOnPC = source.playAudioOnPC
        copy.optimizeGames = source.optimizeGames
        copy.enableHdr = source.enableHdr
        copy.btMouseSupport = source.btMouseSupport
        copy.absoluteTouchMode = source.absoluteTouchMode
        copy.statsOverlay = source.statsOverlay
        copy.screenCurvature = source.screenCurvature
        return copy
    }
}

// MARK: - visionOS Enums

enum VisionBaseResolution: Int, CaseIterable {
    case r720p = 0
    case r1080p = 1
    case r2k = 2
    case r4k = 3
    case r5k = 4
    case r8k = 5

    var label: String {
        switch self {
        case .r720p: "720p"
        case .r1080p: "1080p"
        case .r2k: "2K"
        case .r4k: "4K"
        case .r5k: "5K"
        case .r8k: "8K"
        }
    }

    var baseWidth: Int32 {
        switch self {
        case .r720p: 1280
        case .r1080p: 1920
        case .r2k: 2560
        case .r4k: 3840
        case .r5k: 5120
        case .r8k: 7680
        }
    }

    var baseHeight: Int32 {
        switch self {
        case .r720p: 720
        case .r1080p: 1080
        case .r2k: 1440
        case .r4k: 2160
        case .r5k: 2880
        case .r8k: 4320
        }
    }

    static func from(width: Int32, height: Int32) -> VisionBaseResolution {
        for option in allCases {
            if option.baseHeight == height { return option }
        }
        return .r1080p
    }
}

enum VisionAspectRatio: Int, CaseIterable {
    case normal = 0
    case wide = 1
    case ultrawide = 2

    var label: String {
        switch self {
        case .normal: "Normal"
        case .wide: "Wide"
        case .ultrawide: "Ultrawide"
        }
    }

    /// Width multiplier relative to 16:9 base
    var widthMultiplierNumerator: Int32 {
        switch self {
        case .normal: 16
        case .wide: 21
        case .ultrawide: 32
        }
    }

    var widthMultiplierDenominator: Int32 { 16 }

    func computedWidth(baseWidth: Int32) -> Int32 {
        baseWidth * widthMultiplierNumerator / widthMultiplierDenominator
    }

    static func from(width: Int32, baseWidth: Int32) -> VisionAspectRatio {
        let ratio = Double(width) / Double(baseWidth)
        if ratio > 1.8 { return .ultrawide }
        if ratio > 1.1 { return .wide }
        return .normal
    }
}

enum ScreenCurvature: Int, CaseIterable {
    case flat = 0
    case gentle = 1
    case immersive = 2

    var label: String {
        switch self {
        case .flat: "Flat"
        case .gentle: "Gentle"
        case .immersive: "Immersive"
        }
    }
}
