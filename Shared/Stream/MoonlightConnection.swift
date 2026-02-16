import Foundation

// MARK: - Video Decoder Callbacks

private func drDecoderSetup(_ videoFormat: Int32, _ width: Int32, _ height: Int32, _ redrawRate: Int32, _ context: UnsafeMutableRawPointer?, _ drFlags: Int32) -> Int32 {
    guard let renderer = StreamCallbackRouter.shared.videoDecoder else { return -1 }
    renderer.setup(videoFormat: videoFormat, width: width, height: height, frameRate: redrawRate)
    MoonlightConnection.lastFrameNumber = 0
    MoonlightConnection.activeVideoFormat = videoFormat
    MoonlightConnection.currentVideoStats = VideoStats()
    MoonlightConnection.lastVideoStats = VideoStats()
    return 0
}

private func drStart() {
    StreamCallbackRouter.shared.videoDecoder?.start()
}

private func drStop() {
    StreamCallbackRouter.shared.videoDecoder?.stop()
}

private func drSubmitDecodeUnit(_ decodeUnit: UnsafeMutablePointer<DECODE_UNIT>?) -> Int32 {
    guard let du = decodeUnit?.pointee,
          let renderer = StreamCallbackRouter.shared.videoDecoder else {
        return Int32(DR_NEED_IDR)
    }

    let fullLength = Int(du.fullLength)
    guard let data = malloc(fullLength)?.assumingMemoryBound(to: UInt8.self) else {
        return Int32(DR_NEED_IDR)
    }

    let now = CACurrentMediaTime()
    if MoonlightConnection.lastFrameNumber == 0 {
        MoonlightConnection.currentVideoStats.startTime = now
        MoonlightConnection.lastFrameNumber = du.frameNumber
    } else {
        if now - MoonlightConnection.currentVideoStats.startTime >= 1.0 {
            MoonlightConnection.currentVideoStats.endTime = now
            MoonlightConnection.videoStatsLock.lock()
            MoonlightConnection.lastVideoStats = MoonlightConnection.currentVideoStats
            MoonlightConnection.videoStatsLock.unlock()
            MoonlightConnection.currentVideoStats = VideoStats()
            MoonlightConnection.currentVideoStats.startTime = now
        }

        MoonlightConnection.currentVideoStats.networkDroppedFrames += du.frameNumber - (MoonlightConnection.lastFrameNumber + 1)
        MoonlightConnection.currentVideoStats.totalFrames += du.frameNumber - (MoonlightConnection.lastFrameNumber + 1)
        MoonlightConnection.lastFrameNumber = du.frameNumber
    }

    let hostLatency = Int32(du.frameHostProcessingLatency)
    if hostLatency != 0 {
        if MoonlightConnection.currentVideoStats.minHostProcessingLatency == 0 ||
            hostLatency < MoonlightConnection.currentVideoStats.minHostProcessingLatency {
            MoonlightConnection.currentVideoStats.minHostProcessingLatency = hostLatency
        }
        if hostLatency > MoonlightConnection.currentVideoStats.maxHostProcessingLatency {
            MoonlightConnection.currentVideoStats.maxHostProcessingLatency = hostLatency
        }
        MoonlightConnection.currentVideoStats.framesWithHostProcessingLatency += 1
        MoonlightConnection.currentVideoStats.totalHostProcessingLatency += hostLatency
    }

    MoonlightConnection.currentVideoStats.receivedFrames += 1
    MoonlightConnection.currentVideoStats.totalFrames += 1

    var offset: Int = 0
    var entry = du.bufferList
    while let e = entry?.pointee {
        if e.bufferType != Int32(BUFFER_TYPE_PICDATA) {
            let dataPtr = UnsafeMutableRawPointer(e.data)!.assumingMemoryBound(to: UInt8.self)
            let ret = renderer.submitDecodeBuffer(
                dataPtr,
                length: e.length,
                bufferType: e.bufferType,
                decodeUnit: decodeUnit
            )
            if ret != Int32(DR_OK) {
                free(data)
                return ret
            }
        } else {
            memcpy(data + offset, e.data, Int(e.length))
            offset += Int(e.length)
        }
        entry = e.next
    }

    return renderer.submitDecodeBuffer(data, length: Int32(offset), bufferType: Int32(BUFFER_TYPE_PICDATA), decodeUnit: decodeUnit)
}

// MARK: - Connection Listener Callbacks

private func clConnectionStarted() {
    StreamCallbackRouter.shared.delegate?.connectionStarted()
}

private func clConnectionTerminated(_ errorCode: Int32) {
    StreamCallbackRouter.shared.delegate?.connectionTerminated(errorCode)
}

private func clStageStarting(_ stage: Int32) {
    guard let name = LiGetStageName(stage) else { return }
    StreamCallbackRouter.shared.delegate?.stageStarting(name)
}

private func clStageComplete(_ stage: Int32) {
    guard let name = LiGetStageName(stage) else { return }
    StreamCallbackRouter.shared.delegate?.stageComplete(name)
}

private func clStageFailed(_ stage: Int32, _ errorCode: Int32) {
    guard let name = LiGetStageName(stage) else { return }
    StreamCallbackRouter.shared.delegate?.stageFailed(name, withError: errorCode, portTestFlags: Int32(bitPattern: LiGetPortFlagsFromStage(stage)))
}

private func clRumble(_ controllerNumber: UInt16, _ lowFreqMotor: UInt16, _ highFreqMotor: UInt16) {
    StreamCallbackRouter.shared.delegate?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
}

private func clConnectionStatusUpdate(_ status: Int32) {
    StreamCallbackRouter.shared.delegate?.connectionStatusUpdate(status)
}

private func clSetHdrMode(_ enabled: Bool) {
    StreamCallbackRouter.shared.videoDecoder?.setHdrMode(enabled)
    StreamCallbackRouter.shared.delegate?.setHdrMode(enabled)
}

private func clRumbleTriggers(_ controllerNumber: UInt16, _ leftTrigger: UInt16, _ rightTrigger: UInt16) {
    StreamCallbackRouter.shared.delegate?.rumbleTriggers(controllerNumber, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
}

private func clSetMotionEventState(_ controllerNumber: UInt16, _ motionType: UInt8, _ reportRateHz: UInt16) {
    StreamCallbackRouter.shared.delegate?.setMotionEventState(controllerNumber, motionType: motionType, reportRateHz: reportRateHz)
}

private func clSetControllerLED(_ controllerNumber: UInt16, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    StreamCallbackRouter.shared.delegate?.setControllerLed(controllerNumber, r: r, g: g, b: b)
}

// MARK: - MoonlightConnection

final class MoonlightConnection: @unchecked Sendable {
    private let config: StreamConfiguration
    private let renderer: VideoDecoder

    private var serverInfo = SERVER_INFORMATION()
    private var streamConfig = STREAM_CONFIGURATION()
    private var clCallbacks = CONNECTION_LISTENER_CALLBACKS()
    private var drCallbacks = DECODER_RENDERER_CALLBACKS()
    private var arCallbacks = AUDIO_RENDERER_CALLBACKS()

    private var hostString = [CChar](repeating: 0, count: 256)
    private var appVersionString = [CChar](repeating: 0, count: 32)
    private var gfeVersionString = [CChar](repeating: 0, count: 32)
    private var rtspSessionUrl = [CChar](repeating: 0, count: 128)

    static let initLock = NSLock()
    static let videoStatsLock = NSLock()
    nonisolated(unsafe) static var lastFrameNumber: Int32 = 0
    nonisolated(unsafe) static var activeVideoFormat: Int32 = 0
    nonisolated(unsafe) static var currentVideoStats = VideoStats()
    nonisolated(unsafe) static var lastVideoStats = VideoStats()

    init(config: StreamConfiguration, renderer: VideoDecoder) {
        self.config = config
        self.renderer = renderer

        StreamCallbackRouter.shared.videoDecoder = renderer

        // Host address
        let rawAddress = AddressUtils.parseAddressAndPort(config.host ?? "").address
        strncpy(&hostString, rawAddress.cString(using: .utf8)!, hostString.count - 1)
        if let appVer = config.appVersion {
            strncpy(&appVersionString, appVer.cString(using: .utf8)!, appVersionString.count - 1)
        }
        if let gfe = config.gfeVersion {
            strncpy(&gfeVersionString, gfe.cString(using: .utf8)!, gfeVersionString.count - 1)
        }
        if let rtsp = config.rtspSessionUrl {
            strncpy(&rtspSessionUrl, rtsp.cString(using: .utf8)!, rtspSessionUrl.count - 1)
        }

        LiInitializeServerInformation(&serverInfo)
        serverInfo.address = UnsafePointer(hostString)
        serverInfo.serverInfoAppVersion = UnsafePointer(appVersionString)
        if config.gfeVersion != nil {
            serverInfo.serverInfoGfeVersion = UnsafePointer(gfeVersionString)
        }
        if config.rtspSessionUrl != nil {
            serverInfo.rtspSessionUrl = UnsafePointer(rtspSessionUrl)
        }
        serverInfo.serverCodecModeSupport = config.serverCodecModeSupport

        LiInitializeStreamConfiguration(&streamConfig)
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.fps = config.frameRate
        streamConfig.bitrate = config.bitRate
        streamConfig.supportedVideoFormats = config.supportedVideoFormats
        streamConfig.audioConfiguration = config.audioConfiguration
        streamConfig.encryptionFlags = Int32(ENCFLG_ALL)

        if AddressUtils.isVPNActive() {
            streamConfig.streamingRemotely = Int32(STREAM_CFG_REMOTE)
            streamConfig.packetSize = 1024
        } else {
            streamConfig.streamingRemotely = Int32(STREAM_CFG_AUTO)
            streamConfig.packetSize = 1392
        }

        config.riKey.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            memcpy(&streamConfig.remoteInputAesKey, ptr, min(buf.count, MemoryLayout.size(ofValue: streamConfig.remoteInputAesKey)))
        }
        memset(&streamConfig.remoteInputAesIv, 0, 16)
        var riKeyId = config.riKeyId.bigEndian
        memcpy(&streamConfig.remoteInputAesIv, &riKeyId, MemoryLayout<Int32>.size)

        // Video callbacks
        LiInitializeVideoCallbacks(&drCallbacks)
        drCallbacks.setup = drDecoderSetup
        drCallbacks.start = drStart
        drCallbacks.stop = drStop
        drCallbacks.submitDecodeUnit = drSubmitDecodeUnit
        #if os(visionOS)
        drCallbacks.capabilities = Int32(CAPABILITY_DIRECT_SUBMIT) |
            Int32(CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC) |
            Int32(CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1)
        #else
        drCallbacks.capabilities = Int32(CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC) |
            Int32(CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1)
        #endif

        // Audio callbacks
        LiInitializeAudioCallbacks(&arCallbacks)
        arCallbacks.`init` = AudioRenderer_Init
        arCallbacks.start = AudioRenderer_Start
        arCallbacks.stop = AudioRenderer_Stop
        arCallbacks.cleanup = AudioRenderer_Cleanup
        arCallbacks.decodeAndPlaySample = AudioRenderer_DecodeAndPlaySample
        arCallbacks.capabilities = Int32(CAPABILITY_DIRECT_SUBMIT) | Int32(CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION)

        // Connection listener callbacks
        LiInitializeConnectionCallbacks(&clCallbacks)
        clCallbacks.stageStarting = clStageStarting
        clCallbacks.stageComplete = clStageComplete
        clCallbacks.stageFailed = clStageFailed
        clCallbacks.connectionStarted = clConnectionStarted
        clCallbacks.connectionTerminated = clConnectionTerminated
        // logMessage is a variadic C function pointer — cannot be set from Swift
        clCallbacks.rumble = clRumble
        clCallbacks.connectionStatusUpdate = clConnectionStatusUpdate
        clCallbacks.setHdrMode = clSetHdrMode
        clCallbacks.rumbleTriggers = clRumbleTriggers
        clCallbacks.setMotionEventState = clSetMotionEventState
        clCallbacks.setControllerLED = clSetControllerLED
    }

    func start() {
        Self.initLock.lock()
        LiStartConnection(&serverInfo, &streamConfig, &clCallbacks, &drCallbacks, &arCallbacks, nil, 0, nil, 0)
        Self.initLock.unlock()
    }

    func terminate() {
        LiInterruptConnection()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.initLock.lock()
            LiStopConnection()
            Self.initLock.unlock()
        }
    }

    // MARK: - Video Stats

    func getVideoStats() -> VideoStats? {
        Self.videoStatsLock.lock()
        let stats = Self.lastVideoStats
        Self.videoStatsLock.unlock()
        return stats.endTime != 0 ? stats : nil
    }

    func getActiveCodecName() -> String {
        switch Self.activeVideoFormat {
        case VIDEO_FORMAT_H264:
            return "H.264"
        case VIDEO_FORMAT_H265:
            return "HEVC"
        case VIDEO_FORMAT_H265_MAIN10:
            return LiGetCurrentHostDisplayHdrMode() ? "HEVC Main 10 HDR" : "HEVC Main 10 SDR"
        case VIDEO_FORMAT_AV1_MAIN8:
            return "AV1"
        case VIDEO_FORMAT_AV1_MAIN10:
            return LiGetCurrentHostDisplayHdrMode() ? "AV1 10-bit HDR" : "AV1 10-bit SDR"
        default:
            return "UNKNOWN"
        }
    }

    func getStatsOverlayText() -> String? {
        guard let stats = getVideoStats() else { return nil }

        var rtt: UInt32 = 0
        var variance: UInt32 = 0
        let latencyString: String
        if LiGetEstimatedRttInfo(&rtt, &variance) {
            latencyString = "\(rtt) ms (variance: \(variance) ms)"
        } else {
            latencyString = "N/A"
        }

        var hostProcessingString = ""
        if stats.framesWithHostProcessingLatency != 0 {
            let minLatency = Float(stats.minHostProcessingLatency) / 10.0
            let maxLatency = Float(stats.maxHostProcessingLatency) / 10.0
            let avgLatency = Float(stats.totalHostProcessingLatency) / Float(stats.framesWithHostProcessingLatency) / 10.0
            hostProcessingString = "\nHost processing latency min/max/avg: \(String(format: "%.1f", minLatency))/\(String(format: "%.1f", maxLatency))/\(String(format: "%.1f", avgLatency)) ms"
        }

        let interval = Float(stats.endTime - stats.startTime)
        let fps = Float(stats.totalFrames) / interval
        let dropped = Float(stats.networkDroppedFrames) / interval

        return "Video stream: \(config.width)x\(config.height) \(String(format: "%.2f", fps)) FPS (Codec: \(getActiveCodecName()))\nFrames dropped by your network connection: \(String(format: "%.2f%%", dropped))\nAverage network latency: \(latencyString)\(hostProcessingString)"
    }
}
