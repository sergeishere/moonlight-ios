//
//  AudioStreamHandler.swift
//  Moonlight
//
//  Created by Sergey Dmitriev on 14.11.2024.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//
import AVFoundation
import os.log

public var audioEngine: AVAudioEngine!
public var audioEnvironmentNode: AVAudioEnvironmentNode!
public var audioPlayerNode: AVAudioPlayerNode!
public var audioFormat: AVAudioFormat!
public var opusDecoder: OpaquePointer!
public var opusConfig: OPUS_MULTISTREAM_CONFIGURATION!
public var audioFrameSize: Int = 0
public var destAudioDescription: AudioStreamBasicDescription!

public var destinationFormat: AVAudioFormat!
public var audioConverter: AVAudioConverter!

public var audioBuffer: AVAudioBuffer!

var renderBlock: AUInternalRenderBlock?

let audioQueue: DispatchQueue = DispatchQueue(label: "Audio", qos: .default)

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
//    audioFormat = AVAudioFormat(
//        commonFormat: .pcmFormatInt16,
//        sampleRate: Double(opusConfig.sampleRate),
//        channels: AVAudioChannelCount(opusConfig.channelCount),
//        interleaved: true
//    )
    
    audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(opusConfig.sampleRate),
        channels: AVAudioChannelCount(opusConfig.channelCount),
        interleaved: true
    )
//    dump(audioFormat.streamDescription.pointee)
    
//    destAudioDescription = AudioStreamBasicDescription(
//        mSampleRate: 48000.0,
//        mFormatID: kAudioFormatLinearPCM,
//        mFormatFlags: AudioFormatFlags(kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved),
//        mBytesPerPacket: UInt32(4),           // 1 channels * 4 bytes per float32
//        mFramesPerPacket: 1,                  // For PCM, one frame per packet
//        mBytesPerFrame: UInt32(4),            // 2 channels * 4 bytes per float32
//        mChannelsPerFrame: 2,                 // Stereo
//        mBitsPerChannel: 32,                  // Float32 = 32 bits
//        mReserved: 0
//    )
//    
//    destinationFormat = AVAudioFormat(streamDescription: &destAudioDescription)
//    dump(audioFormat.streamDescription.pointee)
//
    destinationFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(opusConfig.sampleRate),
        channels: AVAudioChannelCount(opusConfig.channelCount),
        interleaved: false
    )
    dump(destinationFormat.streamDescription.pointee)
    
    audioConverter = AVAudioConverter(from: audioFormat, to: destinationFormat)
    audioEngine.attach(audioPlayerNode)
//    audioEngine.attach(audioEnvironmentNode)
    audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: destinationFormat)
//    audioEngine.connect(audioPlayerNode, to: audioEnvironmentNode, format: destinationFormat)
//    audioEngine.connect(audioEnvironmentNode, to: audioEngine.mainMixerNode, format: nil)
//    
//    audioEnvironmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 1)
    
    audioQueue.async {
        audioEngine.prepare()
        try? audioEngine.start()
        audioPlayerNode.play()
    }
    
//    let audioUnit = audioEngine.outputNode.auAudioUnit
//    do {
//        try audioUnit.allocateRenderResources()
//        renderBlock = audioUnit.internalRenderBlock
//    } catch {
//        os_log(.error, "Could not allocate render resources: \(error)")
//    }
    
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
    
//    guard let int16Buffer = AVAudioPCMBuffer(
//        pcmFormat: audioFormat,
//        frameCapacity: AUAudioFrameCount(opusConfig.samplesPerFrame)
//    )
//    else {
//        os_log(.error, "Could not create an output PCM buffer")
//        return
//    }
    
    guard let float32BufferInt = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: AUAudioFrameCount(opusConfig.samplesPerFrame)
    )
    else {
        os_log(.error, "Could not create an output PCM buffer")
        return
    }
    
    let decodedSamples = opus_multistream_decode_float(
        opusDecoder,
        sampleData,
        sampleLength,
        float32BufferInt.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: Float32.self),
        opusConfig.samplesPerFrame,
        0
    )
    
    if decodedSamples > 0 {
        
        let float32Buffer = AVAudioPCMBuffer(
          pcmFormat: destinationFormat,
          frameCapacity: AUAudioFrameCount(decodedSamples)
        )!
        
        float32BufferInt.frameLength = AVAudioFrameCount(decodedSamples)
        
        audioQueue.async {
            do {
                try audioConverter.convert(to: float32Buffer, from: float32BufferInt)
                let time = audioPlayerNode.lastRenderTime.map { audioPlayerNode.playerTime(forNodeTime: $0) } ?? nil
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
