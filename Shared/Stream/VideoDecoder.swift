import Foundation
import VideoToolbox
import AVFoundation
import os

private let log = Logger(subsystem: "com.moonlight-stream", category: "VideoDecoder")

/// Replaces VideoDecoderRenderer.m — decodes video frames using VTDecompressionSession (iOS/tvOS)
/// or AVSampleBufferVideoRenderer (visionOS). Uses AV1FormatHelper for AV1 format description creation.
final class VideoDecoder: @unchecked Sendable {
    private let callbacks: any StreamConnectionDelegate
    private let streamAspectRatio: Float

    #if os(visionOS)
    private let videoRenderer: AVSampleBufferVideoRenderer
    #else
    private var decompressionSession: VTDecompressionSession?
    let frameQueue: FrameQueue
    #endif

    fileprivate var videoFormat: Int32 = 0
    private var frameRate: Int32 = 0
    private var videoWidth: Int32 = 0
    private var videoHeight: Int32 = 0
    private(set) var hdrEnabled = false

    private var parameterSetBuffers: [Data] = []
    private var masteringDisplayColorVolume: Data?
    private var contentLightLevelInfo: Data?
    private var formatDesc: CMVideoFormatDescription?

    // MARK: - Init

    #if os(visionOS)
    init(callbacks: any StreamConnectionDelegate,
         sampleBufferVideoRenderer renderer: AVSampleBufferVideoRenderer,
         streamAspectRatio: Float,
         useFramePacing: Bool) {
        self.callbacks = callbacks
        self.videoRenderer = renderer
        self.streamAspectRatio = streamAspectRatio
    }
    #else
    init(callbacks: any StreamConnectionDelegate,
         frameQueue: FrameQueue,
         streamAspectRatio: Float) {
        self.callbacks = callbacks
        self.frameQueue = frameQueue
        self.streamAspectRatio = streamAspectRatio
    }
    #endif

    // MARK: - Lifecycle

    func setup(videoFormat fmt: Int32, width w: Int32, height h: Int32, frameRate fps: Int32) {
        videoFormat = fmt
        frameRate = fps
        videoWidth = w
        videoHeight = h
    }

    func start() {
        // Render loop is driven by MetalView (iOS/tvOS) or RealityKit (visionOS)
    }

    func stop() {
        #if !os(visionOS)
        destroyDecompressionSession()
        frameQueue.shutdown()
        #endif
    }

    func setHdrMode(_ enabled: Bool) {
        hdrEnabled = enabled

        var hdrMetadata = SS_HDR_METADATA()
        let hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata)
        var metadataChanged = false

        // Access displayPrimaries and whitePoint through raw memory since Swift
        // cannot import anonymous C struct array fields.
        if hasMetadata {
            withUnsafeBytes(of: &hdrMetadata) { buf in
                let u16 = buf.baseAddress!.assumingMemoryBound(to: UInt16.self)
                // Layout: displayPrimaries[3] (6 x UInt16), whitePoint (2 x UInt16),
                //         maxDisplayLuminance (UInt32), minDisplayLuminance (UInt32)
                let r_x = u16[0], r_y = u16[1]
                let g_x = u16[2], g_y = u16[3]
                let b_x = u16[4], b_y = u16[5]
                let wp_x = u16[6], wp_y = u16[7]
                let maxLum = buf.load(fromByteOffset: 16, as: UInt32.self)
                let minLum = buf.load(fromByteOffset: 20, as: UInt32.self)
                let maxCLL = u16[12]
                let maxFALL = u16[13]

                if r_x != 0 && maxLum != 0 {
                    // Build MDCV in big-endian format (GBR order from RGB metadata)
                    var mdcvBytes = Data(count: 24)
                    mdcvBytes.withUnsafeMutableBytes { out in
                        let p = out.baseAddress!.assumingMemoryBound(to: UInt16.self)
                        p[0] = g_x.bigEndian
                        p[1] = g_y.bigEndian
                        p[2] = b_x.bigEndian
                        p[3] = b_y.bigEndian
                        p[4] = r_x.bigEndian
                        p[5] = r_y.bigEndian
                        p[6] = wp_x.bigEndian
                        p[7] = wp_y.bigEndian
                        let u32 = out.baseAddress!.advanced(by: 16).assumingMemoryBound(to: UInt32.self)
                        u32[0] = (maxLum &* 10000).bigEndian
                        u32[1] = minLum.bigEndian
                    }

                    if masteringDisplayColorVolume != mdcvBytes {
                        masteringDisplayColorVolume = mdcvBytes
                        metadataChanged = true
                    }
                } else if masteringDisplayColorVolume != nil {
                    masteringDisplayColorVolume = nil
                    metadataChanged = true
                }

                if maxCLL != 0 && maxFALL != 0 {
                    var cllBytes = Data(count: 4)
                    cllBytes.withUnsafeMutableBytes { out in
                        let p = out.baseAddress!.assumingMemoryBound(to: UInt16.self)
                        p[0] = maxCLL.bigEndian
                        p[1] = maxFALL.bigEndian
                    }

                    if contentLightLevelInfo != cllBytes {
                        contentLightLevelInfo = cllBytes
                        metadataChanged = true
                    }
                } else if contentLightLevelInfo != nil {
                    contentLightLevelInfo = nil
                    metadataChanged = true
                }
            }
        } else {
            if masteringDisplayColorVolume != nil {
                masteringDisplayColorVolume = nil
                metadataChanged = true
            }
            if contentLightLevelInfo != nil {
                contentLightLevelInfo = nil
                metadataChanged = true
            }
        }

        if metadataChanged {
            LiRequestIdrFrame()
        }
    }

    // MARK: - Decode

    /// Called by MoonlightConnection's drSubmitDecodeUnit callback.
    /// `data` is a malloc'd buffer that this method must free for BUFFER_TYPE_PICDATA.
    func submitDecodeBuffer(_ data: UnsafeMutablePointer<UInt8>,
                            length: Int32,
                            bufferType: Int32,
                            decodeUnit du: UnsafeMutablePointer<DECODE_UNIT>?) -> Int32 {
        guard let du = du else {
            free(data)
            return Int32(DR_NEED_IDR)
        }

        let frameType = du.pointee.frameType

        // Construct a new format description on each IDR frame
        if frameType == FRAME_TYPE_IDR {
            if bufferType != Int32(BUFFER_TYPE_PICDATA) {
                if bufferType == Int32(BUFFER_TYPE_VPS) ||
                    bufferType == Int32(BUFFER_TYPE_SPS) ||
                    bufferType == Int32(BUFFER_TYPE_PPS) {
                    let startLen: Int = data[2] == 0x01 ? 3 : 4
                    parameterSetBuffers.append(Data(bytes: data + startLen, count: Int(length) - startLen))
                }
                return Int32(DR_OK)
            }

            formatDesc = nil

            if videoFormat & VIDEO_FORMAT_MASK_H264 != 0 {
                formatDesc = createH264FormatDescription()
                parameterSetBuffers.removeAll()
            } else if videoFormat & VIDEO_FORMAT_MASK_H265 != 0 {
                formatDesc = createHEVCFormatDescription()
                parameterSetBuffers.removeAll()
            } else if videoFormat & VIDEO_FORMAT_MASK_AV1 != 0 {
                let frameData = NSData(bytesNoCopy: data, length: Int(length), freeWhenDone: false)
                formatDesc = AV1FormatHelper.createFormatDescription(
                    forIDRFrame: frameData as Data,
                    contentLightLevelInfo: contentLightLevelInfo,
                    masteringDisplayColorVolume: masteringDisplayColorVolume
                )
            } else {
                fatalError("Unsupported video format")
            }

            #if !os(visionOS)
            if formatDesc != nil {
                if !createDecompressionSession() {
                    log.error("Failed to create VTDecompressionSession")
                    free(data)
                    return Int32(DR_NEED_IDR)
                }
            }
            #endif
        }

        guard let fmtDesc = formatDesc else {
            free(data)
            return Int32(DR_NEED_IDR)
        }

        #if os(visionOS)
        if videoRenderer.status == .failed {
            log.error("Sample buffer video renderer failed: \(String(describing: videoRenderer.error))")
            formatDesc = nil
            free(data)
            return Int32(DR_NEED_IDR)
        }
        #else
        guard decompressionSession != nil else {
            free(data)
            return Int32(DR_NEED_IDR)
        }
        #endif

        // Create block buffer from data — CMBlockBuffer takes ownership of malloc'd data
        var dataBlockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data,
            blockLength: Int(length),
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: Int(length),
            flags: 0,
            blockBufferOut: &dataBlockBuffer
        )
        guard status == noErr, let dataBlock = dataBlockBuffer else {
            log.error("CMBlockBufferCreateWithMemoryBlock failed: \(status)")
            free(data)
            return Int32(DR_NEED_IDR)
        }

        var frameBlockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: 0,
            flags: 0,
            blockBufferOut: &frameBlockBuffer
        )
        guard status == noErr, let frameBlock = frameBlockBuffer else {
            log.error("CMBlockBufferCreateEmpty failed: \(status)")
            return Int32(DR_NEED_IDR)
        }

        // H.264 and HEVC require Annex B → length-delimited conversion
        if videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265) != 0 {
            var lastOffset = -1
            for i in 0..<(Int(length) - 3) {
                if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
                    if lastOffset != -1 {
                        appendNALUnit(to: frameBlock, from: dataBlock, offset: lastOffset, length: i - lastOffset)
                    }
                    lastOffset = i
                }
            }
            if lastOffset != -1 {
                appendNALUnit(to: frameBlock, from: dataBlock, offset: lastOffset, length: Int(length) - lastOffset)
            }
        } else {
            status = CMBlockBufferAppendBufferReference(frameBlock, targetBBuf: dataBlock, offsetToData: 0, dataLength: Int(length), flags: 0)
            if status != noErr {
                log.error("CMBlockBufferAppendBufferReference failed: \(status)")
                return Int32(DR_NEED_IDR)
            }
        }

        var sampleTiming = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTimeMake(value: Int64(du.pointee.presentationTimeMs), timescale: 1000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: frameBlock,
            formatDescription: fmtDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sample = sampleBuffer else {
            log.error("CMSampleBufferCreateReady failed: \(status)")
            return Int32(DR_NEED_IDR)
        }

        #if os(visionOS)
        if videoRenderer.isReadyForMoreMediaData {
            videoRenderer.enqueue(sample)
        }
        #else
        decodeFrame(sample)
        #endif

        if frameType == FRAME_TYPE_IDR {
            callbacks.videoContentShown()
        }

        return Int32(DR_OK)
    }

    // MARK: - Private: Format Descriptions

    private func createH264FormatDescription() -> CMVideoFormatDescription? {
        log.info("Constructing new H264 format description")

        return parameterSetBuffers.withUnsafeBufferPointers { pointers, sizes in
            var desc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers.baseAddress!,
                parameterSetSizes: sizes.baseAddress!,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &desc
            )
            if status != noErr {
                log.error("Failed to create H264 format description: \(status)")
                return nil
            }
            return desc
        }
    }

    private func createHEVCFormatDescription() -> CMVideoFormatDescription? {
        log.info("Constructing new HEVC format description")

        var params: [String: Any] = [:]
        if let cll = contentLightLevelInfo {
            params[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = cll
        }
        if let mdcv = masteringDisplayColorVolume {
            params[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] = mdcv
        }

        return parameterSetBuffers.withUnsafeBufferPointers { pointers, sizes in
            var desc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers.baseAddress!,
                parameterSetSizes: sizes.baseAddress!,
                nalUnitHeaderLength: 4,
                extensions: params as CFDictionary,
                formatDescriptionOut: &desc
            )
            if status != noErr {
                log.error("Failed to create HEVC format description: \(status)")
                return nil
            }
            return desc
        }
    }

    // MARK: - Private: NAL unit conversion

    private func appendNALUnit(to frameBuffer: CMBlockBuffer,
                               from dataBuffer: CMBlockBuffer,
                               offset: Int,
                               length nalLength: Int) {
        let naluStartPrefixSize = 3
        let nalLengthPrefixSize = 4
        let dataLength = nalLength - naluStartPrefixSize

        let oldOffset = CMBlockBufferGetDataLength(frameBuffer)

        var status = CMBlockBufferAppendMemoryBlock(
            frameBuffer,
            memoryBlock: nil,
            length: nalLengthPrefixSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: nalLengthPrefixSize,
            flags: 0
        )
        if status != noErr {
            log.error("CMBlockBufferAppendMemoryBlock failed: \(status)")
            return
        }

        var lengthBytes: [UInt8] = [
            UInt8((dataLength >> 24) & 0xFF),
            UInt8((dataLength >> 16) & 0xFF),
            UInt8((dataLength >> 8) & 0xFF),
            UInt8(dataLength & 0xFF)
        ]
        status = CMBlockBufferReplaceDataBytes(
            with: &lengthBytes,
            blockBuffer: frameBuffer,
            offsetIntoDestination: oldOffset,
            dataLength: nalLengthPrefixSize
        )
        if status != noErr {
            log.error("CMBlockBufferReplaceDataBytes failed: \(status)")
            return
        }

        status = CMBlockBufferAppendBufferReference(
            frameBuffer,
            targetBBuf: dataBuffer,
            offsetToData: offset + naluStartPrefixSize,
            dataLength: dataLength,
            flags: 0
        )
        if status != noErr {
            log.error("CMBlockBufferAppendBufferReference failed: \(status)")
        }
    }

    // MARK: - Private: Decompression (iOS/tvOS)

    #if !os(visionOS)
    private func destroyDecompressionSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
    }

    private func createDecompressionSession() -> Bool {
        destroyDecompressionSession()

        guard let fmtDesc = formatDesc else { return false }

        let is10Bit = (videoFormat & VIDEO_FORMAT_MASK_10BIT) != 0
        let pixelFormat: OSType = is10Bit
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let destAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
        ]

        let decoderConfig: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
        ]

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: fmtDesc,
            decoderSpecification: decoderConfig as CFDictionary,
            imageBufferAttributes: destAttrs as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session else {
            log.error("VTDecompressionSessionCreate failed: \(status)")
            decompressionSession = nil
            return false
        }

        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        decompressionSession = session
        return true
    }

    private func decodeFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let session = decompressionSession else { return }

        let decodeStart = UnsafeMutablePointer<CFTimeInterval>.allocate(capacity: 1)
        decodeStart.pointee = CACurrentMediaTime()

        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: decodeStart,
            infoFlagsOut: &infoFlags
        )

        if status != noErr {
            log.error("VTDecompressionSessionDecodeFrame failed: \(status)")
            decodeStart.deallocate()
        }
    }
    #endif
}

// MARK: - VTDecompressionSession callback

#if !os(visionOS)
private func decompressionCallback(
    _ decompressionOutputRefCon: UnsafeMutableRawPointer?,
    _ sourceFrameRefCon: UnsafeMutableRawPointer?,
    _ status: OSStatus,
    _ infoFlags: VTDecodeInfoFlags,
    _ imageBuffer: CVImageBuffer?,
    _ presentationTimeStamp: CMTime,
    _ presentationDuration: CMTime
) {
    guard let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()

    if status != noErr {
        sourceFrameRefCon?.assumingMemoryBound(to: CFTimeInterval.self).deallocate()
        return
    }

    guard let imageBuffer else {
        sourceFrameRefCon?.assumingMemoryBound(to: CFTimeInterval.self).deallocate()
        return
    }

    var decodeStartTime: CFTimeInterval = 0
    if let refcon = sourceFrameRefCon {
        let ptr = refcon.assumingMemoryBound(to: CFTimeInterval.self)
        decodeStartTime = ptr.pointee
        ptr.deallocate()
    }

    let frame = VideoFrame(pixelBuffer: imageBuffer)!
    frame.decodeTime = CACurrentMediaTime() - decodeStartTime
    frame.isHdr = decoder.hdrEnabled
    frame.is10Bit = (decoder.videoFormat & VIDEO_FORMAT_MASK_10BIT) != 0

    if decoder.videoFormat & VIDEO_FORMAT_MASK_H264 != 0 {
        frame.colorSpace = 709
    } else {
        frame.colorSpace = frame.is10Bit ? 2020 : 709
    }

    decoder.frameQueue.enqueue(frame)
}
#endif

// MARK: - Helper extension for parameter set buffers

private extension Array where Element == Data {
    func withUnsafeBufferPointers<R>(_ body: (UnsafeBufferPointer<UnsafePointer<UInt8>>, UnsafeBufferPointer<Int>) -> R) -> R {
        let count = self.count
        var pointers = [UnsafePointer<UInt8>?](repeating: nil, count: count)
        var sizes = [Int](repeating: 0, count: count)

        for i in 0..<count {
            self[i].withUnsafeBytes { buf in
                pointers[i] = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                sizes[i] = buf.count
            }
        }

        return pointers.withUnsafeBufferPointer { ptrBuf in
            sizes.withUnsafeBufferPointer { sizeBuf in
                let nonOptPtrs = UnsafeBufferPointer(
                    start: UnsafeRawPointer(ptrBuf.baseAddress!).assumingMemoryBound(to: UnsafePointer<UInt8>.self),
                    count: count
                )
                return body(nonOptPtrs, sizeBuf)
            }
        }
    }
}
