import AVFoundation
import os.log

nonisolated(unsafe) var audioEngine: AVAudioEngine!
nonisolated(unsafe) var audioEnvironmentNode: AVAudioEnvironmentNode!
nonisolated(unsafe) var audioPlayerNode: AVAudioPlayerNode!
nonisolated(unsafe) var audioFormat: AVAudioFormat!
nonisolated(unsafe) var opusDecoder: OpaquePointer!
nonisolated(unsafe) var opusConfig: OPUS_MULTISTREAM_CONFIGURATION!
nonisolated(unsafe) var audioFrameSize: Int = 0
nonisolated(unsafe) var destAudioDescription: AudioStreamBasicDescription!

nonisolated(unsafe) var destinationFormat: AVAudioFormat!
nonisolated(unsafe) var audioConverter: AVAudioConverter!

nonisolated(unsafe) var audioBuffer: AVAudioBuffer!

private let audioQueue = DispatchQueue(label: "AudioRendering", qos: .default)

@_cdecl("ArInit") func ArInit(
    audioConfiguration: Int32,
    opusConfigPointer: POPUS_MULTISTREAM_CONFIGURATION,
    context: UnsafeMutableRawPointer,
    flags: Int32
) -> Int32 {

    opusConfig = opusConfigPointer.pointee
    do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setPreferredSampleRate(Double(opusConfig.sampleRate))
        try audioSession.setPreferredIOBufferDuration(TimeInterval(opusConfig.samplesPerFrame / opusConfig.sampleRate))
    } catch {
        os_log(.error, "Failed to set preferred sample rate: \(error)")
    }

    audioFrameSize = Int(opusConfig.samplesPerFrame) * MemoryLayout<Int16>.size

    var opusDecodeCreateError: Int32 = 0
    opusDecoder = opus_multistream_decoder_create(
        opusConfig.sampleRate,
        opusConfig.channelCount,
        opusConfig.streams,
        opusConfig.coupledStreams,
        &opusConfig.mapping.0,
        &opusDecodeCreateError
    )

    guard opusDecoder != nil else {
        os_log(.error, "Failed to create Opus decoder")
        ArCleanup()
        return -1
    }

    audioEngine = AVAudioEngine()
    audioEngine.reset()
    audioPlayerNode = AVAudioPlayerNode()
    audioEnvironmentNode = AVAudioEnvironmentNode()

    audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(opusConfig.sampleRate),
        channels: AVAudioChannelCount(opusConfig.channelCount),
        interleaved: true
    )

    destinationFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(opusConfig.sampleRate),
        channels: AVAudioChannelCount(opusConfig.channelCount),
        interleaved: false
    )

    audioConverter = AVAudioConverter(from: audioFormat, to: destinationFormat)
    audioEngine.attach(audioPlayerNode)
    audioEngine.attach(audioEnvironmentNode)
    audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: destinationFormat)

    audioQueue.async {
        audioEngine.prepare()
        try? audioEngine.start()
        audioPlayerNode.play()
    }

    return 0
}

@_cdecl("ArCleanup") func ArCleanup() {
    if opusDecoder != nil {
        opusDecoder = nil
    }

    if audioEngine != nil {
        audioEngine.reset()
        audioEngine.stop()
        audioEngine = nil
    }

    if audioPlayerNode != nil {
        audioPlayerNode = nil
    }
}

@_cdecl("ArDecodeAndPlaySample") func ArDecodeAndPlaySample(
    sampleData: UnsafeMutablePointer<CChar>,
    sampleLength: Int32
) {
    guard let float32BufferInt = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: AUAudioFrameCount(opusConfig.samplesPerFrame)
    )
    else {
        os_log(.error, "Could not create an output PCM buffer")
        return
    }

    guard let pcmDataPtr = float32BufferInt.mutableAudioBufferList.pointee.mBuffers.mData else { return }
    let decodedSamples = opus_multistream_decode_float(
        opusDecoder,
        sampleData,
        sampleLength,
        pcmDataPtr.assumingMemoryBound(to: Float32.self),
        opusConfig.samplesPerFrame,
        0
    )

    if decodedSamples > 0 {
        guard let float32Buffer = AVAudioPCMBuffer(
            pcmFormat: destinationFormat,
            frameCapacity: AUAudioFrameCount(decodedSamples)
        ) else { return }

        float32BufferInt.frameLength = AVAudioFrameCount(decodedSamples)

        audioQueue.async {
            do {
                try audioConverter.convert(to: float32Buffer, from: float32BufferInt)
                audioPlayerNode.scheduleBuffer(float32Buffer)
            } catch {
                os_log(.error, "Could not convert to float32 buffer")
            }
        }
    } else {
        os_log(.error, "Could not decode sample data")
        return
    }
}
