import SwiftUI
import SwiftData
import AVFoundation
import VideoToolbox

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allSettings: [StreamSettings]
    private var settings: StreamSettings {
        if let existing = allSettings.first {
            return existing
        }
        let new = StreamSettings()
        modelContext.insert(new)
        return new
    }

    // MARK: - Local State

    @State private var selectedResolution: ResolutionOption = .r720p
    @State private var customWidth: Int32 = 0
    @State private var customHeight: Int32 = 0
    @State private var selectedFramerate: FramerateOption = .fps60
    @State private var bitrateKbps: Int32 = 10000
    @State private var onscreenControls: OnScreenControlsLevel = .auto
    @State private var touchMode: TouchMode = .relative
    @State private var optimizeGames = true
    @State private var multiController = true
    @State private var swapABXYButtons = false
    @State private var playAudioOnPC = false
    @State private var preferredCodec: PreferredCodec = .auto
    @State private var enableHdr = false
    @State private var useFramePacing = false
    @State private var statsOverlay = false
    @State private var showCustomResolution = false

    var body: some View {
        NavigationStack {
            Form {
                resolutionSection
                framerateSection
                bitrateSection
                #if !os(tvOS)
                inputSection
                #endif
                gameSettingsSection
                audioSection
                videoSection
                advancedSection
            }
            .navigationTitle("Settings")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear { loadSettings() }
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        Section("Resolution") {
            Picker("Resolution", selection: $selectedResolution) {
                ForEach(availableResolutions, id: \.self) { res in
                    Text(res.label).tag(res)
                }
            }
            .onChange(of: selectedResolution) { _, newValue in
                if newValue == .custom {
                    showCustomResolution = true
                } else {
                    updateBitrate()
                }
            }

            if selectedResolution == .custom || customWidth > 0 {
                HStack {
                    Text("Stream resolution")
                    Spacer()
                    Text("\(effectiveWidth) x \(effectiveHeight)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Custom Resolution", isPresented: $showCustomResolution) {
            TextField("Width", value: $customWidth, format: .number)
                .keyboardType(.numberPad)
            TextField("Height", value: $customHeight, format: .number)
                .keyboardType(.numberPad)
            Button("OK") {
                customWidth = max(256, min(customWidth, maxResolutionDimension))
                customHeight = max(256, min(customHeight, maxResolutionDimension))
                updateBitrate()
            }
            Button("Cancel", role: .cancel) {
                if customWidth == 0 || customHeight == 0 {
                    selectedResolution = .r720p
                }
            }
        }
    }

    // MARK: - Framerate

    private var framerateSection: some View {
        Section("Frame Rate") {
            Picker("FPS", selection: $selectedFramerate) {
                ForEach(availableFramerates, id: \.self) { fps in
                    Text(fps.label).tag(fps)
                }
            }
            .onChange(of: selectedFramerate) { _, _ in
                updateBitrate()
            }
        }
    }

    // MARK: - Bitrate

    private var bitrateSection: some View {
        Section("Bitrate") {
            VStack(alignment: .leading) {
                Text(String(format: "Bitrate: %.1f Mbps", Double(bitrateKbps) / 1000.0))
                Slider(
                    value: Binding(
                        get: { Double(bitrateSliderIndex) },
                        set: { bitrateKbps = Self.bitrateTable[Int($0)] }
                    ),
                    in: 0...Double(Self.bitrateTable.count - 1),
                    step: 1
                )
            }
        }
    }

    // MARK: - Input

    #if !os(tvOS)
    private var inputSection: some View {
        Section("Input") {
            Picker("Touch Mode", selection: $touchMode) {
                Text("Trackpad").tag(TouchMode.relative)
                Text("Direct Touch").tag(TouchMode.absolute)
            }

            Picker("On-Screen Controls", selection: $onscreenControls) {
                Text("Off").tag(OnScreenControlsLevel.off)
                Text("Auto").tag(OnScreenControlsLevel.auto)
                Text("Simple").tag(OnScreenControlsLevel.simple)
                Text("Full").tag(OnScreenControlsLevel.full)
            }
            .disabled(touchMode == .absolute)
        }
    }
    #endif

    // MARK: - Game Settings

    private var gameSettingsSection: some View {
        Section("Game Settings") {
            Toggle("Optimize Game Settings", isOn: $optimizeGames)
            Toggle("Multi-Controller Mode", isOn: $multiController)
            Toggle("Swap A/B X/Y Buttons", isOn: $swapABXYButtons)
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        Section("Audio") {
            Toggle("Play Audio on PC", isOn: $playAudioOnPC)
        }
    }

    // MARK: - Video

    private var videoSection: some View {
        Section("Video") {
            Picker("Preferred Codec", selection: $preferredCodec) {
                Text("H.264").tag(PreferredCodec.h264)
                if hevcSupported {
                    Text("HEVC").tag(PreferredCodec.hevc)
                }
                if av1Supported {
                    Text("AV1").tag(PreferredCodec.av1)
                }
                Text("Auto").tag(PreferredCodec.auto)
            }

            if hdrCapable {
                Toggle("HDR", isOn: $enableHdr)
            } else {
                HStack {
                    Text("HDR")
                    Spacer()
                    Text("Unsupported")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Frame Pacing", isOn: $useFramePacing)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Stats Overlay", isOn: $statsOverlay)
        }
    }

    // MARK: - Resolution Options

    private var availableResolutions: [ResolutionOption] {
        var options: [ResolutionOption] = [.r360p, .r720p, .r1080p]
        if hevcSupported {
            options.append(.r1440p)
            options.append(.r4k)
        }
        #if !os(tvOS)
        options.append(.nativeSafe)
        options.append(.nativeFull)
        #endif
        options.append(.custom)
        return options
    }

    // MARK: - Framerate Options

    private var availableFramerates: [FramerateOption] {
        var options: [FramerateOption] = [.fps30, .fps60]
        if supportsHighFPS {
            options.append(.fps90)
            options.append(.fps120)
        }
        return options
    }

    private var supportsHighFPS: Bool {
        #if os(visionOS)
        return false
        #else
        return UIScreen.main.maximumFramesPerSecond > 62
        #endif
    }

    // MARK: - Codec Support

    private var hevcSupported: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    }

    private var av1Supported: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    private var hdrCapable: Bool {
        hevcSupported && (AVPlayer.availableHDRModes.rawValue & AVPlayer.HDRMode.hdr10.rawValue) != 0
    }

    private var maxResolutionDimension: Int32 {
        hevcSupported ? 8192 : 4096
    }

    // MARK: - Effective Resolution

    private var effectiveWidth: Int32 {
        if selectedResolution == .custom {
            return customWidth > 0 ? customWidth : 1280
        }
        return selectedResolution.width
    }

    private var effectiveHeight: Int32 {
        if selectedResolution == .custom {
            return customHeight > 0 ? customHeight : 720
        }
        return selectedResolution.height
    }

    // MARK: - Bitrate Calculation

    private static let bitrateTable: [Int32] = [
        500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000,
        8000, 9000, 10000, 12000, 15000, 18000, 20000, 30000, 40000,
        50000, 60000, 70000, 80000, 100000, 120000, 150000,
    ]

    private var bitrateSliderIndex: Int {
        for (i, value) in Self.bitrateTable.enumerated() {
            if bitrateKbps <= value { return i }
        }
        return Self.bitrateTable.count - 1
    }

    private func updateBitrate() {
        let width = effectiveWidth
        let height = effectiveHeight
        let fps = selectedFramerate.value

        let frameRateFactor: Float = if fps <= 60 {
            Float(fps) / 30.0
        } else {
            (sqrtf(Float(fps) / 60.0) * 60.0) / 30.0
        }

        let resTable: [(pixels: Int, factor: Int)] = [
            (640 * 360, 1),
            (854 * 480, 2),
            (1280 * 720, 5),
            (1920 * 1080, 10),
            (2560 * 1440, 20),
            (3840 * 2160, 40),
        ]

        let pixels = Int(width) * Int(height)
        var resolutionFactor: Float = 1

        for i in 0..<resTable.count {
            if pixels == resTable[i].pixels {
                resolutionFactor = Float(resTable[i].factor)
                break
            } else if pixels < resTable[i].pixels {
                if i == 0 {
                    resolutionFactor = Float(resTable[i].factor)
                } else {
                    let prev = resTable[i - 1]
                    let curr = resTable[i]
                    resolutionFactor = Float(pixels - prev.pixels) / Float(curr.pixels - prev.pixels)
                        * Float(curr.factor - prev.factor) + Float(prev.factor)
                }
                break
            } else if i == resTable.count - 1 {
                resolutionFactor = Float(resTable[i].factor)
            }
        }

        let defaultBitrate = Int32(roundf(resolutionFactor * frameRateFactor) * 1000)
        bitrateKbps = min(defaultBitrate, 100000)
    }

    // MARK: - Load / Save

    private func loadSettings() {
        let s = settings

        // Resolution
        let w = s.width
        let h = s.height
        selectedResolution = ResolutionOption.from(width: w, height: h)
        if selectedResolution == .custom {
            customWidth = w
            customHeight = h
        }

        // Framerate
        selectedFramerate = FramerateOption.from(value: s.framerate)

        // Bitrate
        bitrateKbps = s.bitrate

        // Input
        onscreenControls = s.onscreenControlsLevel
        touchMode = s.absoluteTouchMode ? .absolute : .relative

        // Game settings
        optimizeGames = s.optimizeGames
        multiController = s.multiController
        swapABXYButtons = s.swapABXYButtons

        // Audio
        playAudioOnPC = s.playAudioOnPC

        // Video
        preferredCodec = s.codec
        enableHdr = s.enableHdr
        useFramePacing = s.useFramePacing

        // Advanced
        statsOverlay = s.statsOverlay
    }

    private func saveSettings() {
        let s = settings

        s.width = effectiveWidth
        s.height = effectiveHeight
        s.framerate = selectedFramerate.value
        s.bitrate = bitrateKbps
        s.onscreenControlsLevel = onscreenControls
        s.absoluteTouchMode = touchMode == .absolute
        s.optimizeGames = optimizeGames
        s.multiController = multiController
        s.swapABXYButtons = swapABXYButtons
        s.playAudioOnPC = playAudioOnPC
        s.codec = preferredCodec
        s.enableHdr = enableHdr
        s.useFramePacing = useFramePacing
        s.statsOverlay = statsOverlay

        // Sync to UserDefaults for Obj-C code
        let defaults = UserDefaults.standard
        defaults.set(Int(s.bitrate), forKey: "bitrate")
        defaults.set(Int(s.framerate), forKey: "framerate")
        defaults.set(Int(s.height), forKey: "height")
        defaults.set(Int(s.width), forKey: "width")
        defaults.set(Int(s.audioConfig), forKey: "audioConfig")
        defaults.set(Int(s.onscreenControls), forKey: "onscreenControls")
        defaults.set(s.preferredCodec, forKey: "preferredCodec")
        defaults.set(s.useFramePacing, forKey: "useFramePacing")
        defaults.set(s.multiController, forKey: "multiController")
        defaults.set(s.swapABXYButtons, forKey: "swapABXYButtons")
        defaults.set(s.playAudioOnPC, forKey: "playAudioOnPC")
        defaults.set(s.optimizeGames, forKey: "optimizeGames")
        defaults.set(s.enableHdr, forKey: "enableHdr")
        defaults.set(s.btMouseSupport, forKey: "btMouseSupport")
        defaults.set(s.absoluteTouchMode, forKey: "absoluteTouchMode")
        defaults.set(s.statsOverlay, forKey: "statsOverlay")
    }
}

// MARK: - Supporting Types

private enum TouchMode {
    case relative, absolute
}

enum ResolutionOption: Hashable {
    case r360p, r720p, r1080p, r1440p, r4k
    case nativeSafe, nativeFull
    case custom

    var label: String {
        switch self {
        case .r360p: "360p"
        case .r720p: "720p"
        case .r1080p: "1080p"
        case .r1440p: "1440p"
        case .r4k: "4K"
        case .nativeSafe: "Native (Safe Area)"
        case .nativeFull: "Native (Full Screen)"
        case .custom: "Custom"
        }
    }

    var width: Int32 {
        switch self {
        case .r360p: 640
        case .r720p: 1280
        case .r1080p: 1920
        case .r1440p: 2560
        case .r4k: 3840
        case .nativeSafe: Int32(nativeSafeSize.width)
        case .nativeFull: Int32(nativeFullSize.width)
        case .custom: 0
        }
    }

    var height: Int32 {
        switch self {
        case .r360p: 360
        case .r720p: 720
        case .r1080p: 1080
        case .r1440p: 1440
        case .r4k: 2160
        case .nativeSafe: Int32(nativeSafeSize.height)
        case .nativeFull: Int32(nativeFullSize.height)
        case .custom: 0
        }
    }

    static func from(width: Int32, height: Int32) -> ResolutionOption {
        for option in [r360p, r720p, r1080p, r1440p, r4k] {
            if option.width == width && option.height == height {
                return option
            }
        }
        return .custom
    }

    private var nativeSafeSize: CGSize {
        #if os(visionOS)
        CGSize(width: 1920, height: 1080)
        #else
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        let scale = window?.screen.scale ?? 2.0
        let frame = window?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let insets = window?.safeAreaInsets ?? .zero
        return CGSize(
            width: (frame.width - insets.left - insets.right) * scale,
            height: frame.height * scale
        )
        #endif
    }

    private var nativeFullSize: CGSize {
        #if os(visionOS)
        CGSize(width: 1920, height: 1080)
        #else
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        let scale = window?.screen.scale ?? 2.0
        let frame = window?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGSize(width: frame.width * scale, height: frame.height * scale)
        #endif
    }
}

enum FramerateOption: Hashable {
    case fps30, fps60, fps90, fps120

    var label: String {
        switch self {
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        case .fps90: "90 FPS"
        case .fps120: "120 FPS"
        }
    }

    var value: Int32 {
        switch self {
        case .fps30: 30
        case .fps60: 60
        case .fps90: 90
        case .fps120: 120
        }
    }

    static func from(value: Int32) -> FramerateOption {
        switch value {
        case 30: .fps30
        case 90: .fps90
        case 120: .fps120
        default: .fps60
        }
    }
}
