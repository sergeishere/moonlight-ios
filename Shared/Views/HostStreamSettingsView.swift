import SwiftUI
import SwiftData
import AVFoundation
import VideoToolbox

struct HostStreamSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let host: Host

    @Query(filter: #Predicate<StreamSettings> { $0.isGlobalDefaults == true })
    private var globalSettings: [StreamSettings]

    // MARK: - Local State

    @State private var selectedResolution: ResolutionOption = .r720p
    @State private var selectedFramerate: FramerateOption = .fps60
    @State private var bitrateKbps: Int32 = 10000
    @State private var onscreenControls: OnScreenControlsSetting = .auto
    @State private var touchMode: TouchMode = .relative
    @State private var optimizeGames = true
    @State private var multiController = true
    @State private var swapABXYButtons = false
    @State private var playAudioOnPC = false
    @State private var preferredCodec: PreferredCodec = .auto
    @State private var enableHdr = false
    @State private var useFramePacing = false
    @State private var statsOverlay = false

    #if os(visionOS)
    @State private var visionBase: VisionBaseResolution = .r1080p
    @State private var visionAspect: VisionAspectRatio = .normal
    @State private var screenCurvature: ScreenCurvature = .gentle
    #endif

    var body: some View {
        NavigationStack {
            Form {
                resolutionSection
                framerateSection
                bitrateSection
                #if os(visionOS)
                screenSection
                #elseif !os(tvOS)
                inputSection
                #endif
                gameSettingsSection
                audioSection
                videoSection
                advancedSection
            }
            .navigationTitle(host.name)
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
            .onAppear { ensureSettingsAndLoad() }
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        #if os(visionOS)
        Section {
            Picker("Base", selection: $visionBase) {
                ForEach(availableVisionResolutions, id: \.self) { res in
                    Text(res.label).tag(res)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: visionBase) { _, _ in
                syncVisionResolution()
                updateBitrate()
            }

            Picker("Aspect", selection: $visionAspect) {
                ForEach(VisionAspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: visionAspect) { _, _ in
                syncVisionResolution()
                updateBitrate()
            }
        } header: {
            HStack {
                Text("Resolution")
                Spacer()
                Text("\(visionAspect.computedWidth(baseWidth: visionBase.baseWidth)) × \(visionBase.baseHeight)")
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Section {
            Picker("Resolution", selection: $selectedResolution) {
                ForEach(availableResolutions, id: \.self) { res in
                    Text(res == .nativeFull ? "Native" : res.label).tag(res)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedResolution) { _, _ in updateBitrate() }
        } header: {
            HStack {
                Text("Resolution")
                Spacer()
                Text("\(effectiveWidth) × \(effectiveHeight)")
                    .foregroundStyle(.secondary)
            }
        }
        #endif
    }

    // MARK: - Framerate

    private var framerateSection: some View {
        Section("Frame Rate") {
            Picker("FPS", selection: $selectedFramerate) {
                ForEach(availableFramerates, id: \.self) { fps in
                    Text(fps.label).tag(fps)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedFramerate) { _, _ in updateBitrate() }
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

    // MARK: - Screen (visionOS)

    #if os(visionOS)
    private var screenSection: some View {
        Section("Screen") {
            Picker("Curvature", selection: $screenCurvature) {
                ForEach(ScreenCurvature.allCases, id: \.self) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    #endif

    // MARK: - Input

    #if !os(tvOS) && !os(visionOS)
    private var inputSection: some View {
        Section("Input") {
            Picker("Touch Mode", selection: $touchMode) {
                Text("Trackpad").tag(TouchMode.relative)
                Text("Direct Touch").tag(TouchMode.absolute)
            }

            Picker("On-Screen Controls", selection: $onscreenControls) {
                Text("Off").tag(OnScreenControlsSetting.off)
                Text("Auto").tag(OnScreenControlsSetting.auto)
                Text("Simple").tag(OnScreenControlsSetting.simple)
                Text("Full").tag(OnScreenControlsSetting.full)
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
            .pickerStyle(.segmented)

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

    // MARK: - Device Native Resolution

    #if !os(visionOS)
    private var deviceNativeHeight: Int32 {
        Int32(min(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height))
    }
    #endif

    // MARK: - Available Options

    private var availableResolutions: [ResolutionOption] {
        #if os(visionOS)
        return [.r720p, .r1080p, .r1440p, .r4k]  // unused on visionOS (uses VisionBaseResolution pickers)
        #else
        let nativeH = deviceNativeHeight
        var options: [ResolutionOption] = []
        for res: ResolutionOption in [.r360p, .r480p, .r720p, .r1080p, .r1440p, .r4k] {
            if res.height > nativeH { continue }
            if res.height > 1080 && !hevcSupported { continue }
            options.append(res)
        }
        let nativeMatchesStandard = [ResolutionOption.r360p, .r480p, .r720p, .r1080p, .r1440p, .r4k].contains {
            $0.width == ResolutionOption.nativeFull.width && $0.height == ResolutionOption.nativeFull.height
        }
        if !nativeMatchesStandard {
            options.append(.nativeFull)
        }
        return options
        #endif
    }

    #if os(visionOS)
    private var availableVisionResolutions: [VisionBaseResolution] {
        [.r720p, .r1080p, .r2k, .r4k, .r5k, .r8k]
    }
    #endif

    private var availableFramerates: [FramerateOption] {
        var options: [FramerateOption] = [.fps30, .fps60]
        #if os(visionOS)
        options.append(.fps90)
        #else
        if supportsHighFPS {
            options.append(.fps90)
            options.append(.fps120)
        }
        #endif
        return options
    }

    #if !os(visionOS)
    private var supportsHighFPS: Bool {
        UIScreen.main.maximumFramesPerSecond > 62
    }
    #endif

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

    // MARK: - Effective Resolution

    private var effectiveWidth: Int32 {
        #if os(visionOS)
        return visionAspect.computedWidth(baseWidth: visionBase.baseWidth)
        #else
        return selectedResolution.width
        #endif
    }

    private var effectiveHeight: Int32 {
        #if os(visionOS)
        return visionBase.baseHeight
        #else
        return selectedResolution.height
        #endif
    }

    // MARK: - Bitrate

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

    // MARK: - visionOS helpers

    #if os(visionOS)
    private func syncVisionResolution() {
        // Update the underlying resolution from visionOS pickers
        // (selectedResolution is not used on visionOS)
    }
    #endif

    // MARK: - Load / Save

    private func ensureSettingsAndLoad() {
        if host.streamSettings == nil {
            let source = globalSettings.first ?? StreamSettings()
            let copy = StreamSettings.makeCopy(from: source)
            copy.host = host
            modelContext.insert(copy)
            host.streamSettings = copy
        }
        loadSettings()
    }

    private func loadSettings() {
        guard let s = host.streamSettings else { return }

        // Resolution
        #if os(visionOS)
        visionBase = VisionBaseResolution.from(width: s.width, height: s.height)
        visionAspect = VisionAspectRatio.from(width: s.width, baseWidth: visionBase.baseWidth)
        screenCurvature = s.curvature
        #else
        selectedResolution = ResolutionOption.from(width: s.width, height: s.height)
        #endif

        selectedFramerate = FramerateOption.from(value: s.framerate)
        bitrateKbps = s.bitrate
        onscreenControls = s.onscreenControlsLevel
        touchMode = s.absoluteTouchMode ? .absolute : .relative
        optimizeGames = s.optimizeGames
        multiController = s.multiController
        swapABXYButtons = s.swapABXYButtons
        playAudioOnPC = s.playAudioOnPC
        preferredCodec = s.codec
        enableHdr = s.enableHdr
        useFramePacing = s.useFramePacing
        statsOverlay = s.statsOverlay
    }

    private func saveSettings() {
        guard let s = host.streamSettings else { return }

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

        #if os(visionOS)
        s.curvature = screenCurvature
        #endif

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

// MARK: - Private Types

private enum TouchMode {
    case relative, absolute
}
