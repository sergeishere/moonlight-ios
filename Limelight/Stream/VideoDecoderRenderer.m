//
//  VideoDecoderRenderer.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "VideoDecoderRenderer.h"
#import "StreamView.h"
#import "VideoFrame.h"

#include <VideoToolbox/VideoToolbox.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/cbs.h>
#include <libavcodec/cbs_av1.h>
#include <libavformat/avio.h>
#include <libavutil/mem.h>

// Private libavformat API for writing the AV1 Codec Configuration Box
extern int ff_isom_write_av1c(AVIOContext *pb, const uint8_t *buf, int size,
                              int write_seq_header);

@implementation VideoDecoderRenderer {
    id<ConnectionCallbacks> _callbacks;
    float _streamAspectRatio;

#if TARGET_OS_VISION
    AVSampleBufferVideoRenderer* _videoRenderer;
#else
    VTDecompressionSessionRef _decompressionSession;
    FrameQueue *_frameQueue;
    dispatch_queue_t _vtQueue;
#endif

    int videoFormat;
    int frameRate;
    int videoWidth;
    int videoHeight;
    BOOL _hdrEnabled;

    NSMutableArray *parameterSetBuffers;
    NSData *masteringDisplayColorVolume;
    NSData *contentLightLevelInfo;
    CMVideoFormatDescriptionRef formatDesc;
}

#if TARGET_OS_VISION

- (id)initWithCallbacks:(id<ConnectionCallbacks>)callbacks
    sampleBufferVideoRenderer:(AVSampleBufferVideoRenderer*)renderer
            streamAspectRatio:(float)aspectRatio
               useFramePacing:(BOOL)useFramePacing
{
    self = [super init];
    _videoRenderer = renderer;
    _callbacks = callbacks;
    _streamAspectRatio = aspectRatio;
    parameterSetBuffers = [[NSMutableArray alloc] init];
    if (formatDesc != nil) {
        CFRelease(formatDesc);
        formatDesc = nil;
    }
    return self;
}

#else

- (id)initWithCallbacks:(id<ConnectionCallbacks>)callbacks
             frameQueue:(FrameQueue *)frameQueue
      streamAspectRatio:(float)aspectRatio
{
    self = [super init];
    _callbacks = callbacks;
    _frameQueue = frameQueue;
    _streamAspectRatio = aspectRatio;
    _vtQueue = dispatch_queue_create("com.moonlight.vtdecode", DISPATCH_QUEUE_SERIAL);
    parameterSetBuffers = [[NSMutableArray alloc] init];
    return self;
}

#endif

- (void)setupWithVideoFormat:(int)fmt width:(int)w height:(int)h frameRate:(int)fps
{
    videoFormat = fmt;
    frameRate = fps;
    videoWidth = w;
    videoHeight = h;
}

- (void)start
{
    // For Metal path, the render loop is driven by MetalView's render thread.
    // For visionOS, no action needed here either.
}

- (void)stop
{
#if !TARGET_OS_VISION
    [self destroyDecompressionSession];
    [_frameQueue shutdown];
#endif
}

#if !TARGET_OS_VISION

- (void)destroyDecompressionSession
{
    if (_decompressionSession) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }
}

- (BOOL)createDecompressionSession
{
    [self destroyDecompressionSession];

    if (!formatDesc) return NO;

    // Output pixel buffer attributes
    NSDictionary *destImageAttrs;
    BOOL is10Bit = (videoFormat & VIDEO_FORMAT_MASK_10BIT) != 0;

    if (is10Bit) {
        destImageAttrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
            (id)kCVPixelBufferWidthKey: @(videoWidth),
            (id)kCVPixelBufferHeightKey: @(videoHeight),
        };
    } else {
        destImageAttrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
            (id)kCVPixelBufferWidthKey: @(videoWidth),
            (id)kCVPixelBufferHeightKey: @(videoHeight),
        };
    }

    // Decoder configuration
    NSDictionary *decoderConfig = @{
        (id)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: @YES,
    };

    VTDecompressionOutputCallbackRecord callbackRecord;
    callbackRecord.decompressionOutputCallback = decompressionCallback;
    callbackRecord.decompressionOutputRefCon = (__bridge void *)self;

    OSStatus status = VTDecompressionSessionCreate(
        kCFAllocatorDefault,
        formatDesc,
        (__bridge CFDictionaryRef)decoderConfig,
        (__bridge CFDictionaryRef)destImageAttrs,
        &callbackRecord,
        &_decompressionSession);

    if (status != noErr) {
        Log(LOG_E, @"VTDecompressionSessionCreate failed: %d", (int)status);
        _decompressionSession = NULL;
        return NO;
    }

    // Request real-time decoding
    VTSessionSetProperty(_decompressionSession,
                         kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);

    return YES;
}

static void decompressionCallback(void *decompressionOutputRefCon,
                                   void *sourceFrameRefCon,
                                   OSStatus status,
                                   VTDecodeInfoFlags infoFlags,
                                   CVImageBufferRef imageBuffer,
                                   CMTime presentationTimeStamp,
                                   CMTime presentationDuration)
{
    VideoDecoderRenderer *self = (__bridge VideoDecoderRenderer *)decompressionOutputRefCon;

    if (status != noErr) {
        Log(LOG_E, @"VTDecompressionSession decode error: %d", (int)status);
        return;
    }

    if (!imageBuffer) {
        Log(LOG_W, @"VTDecompressionSession returned nil imageBuffer");
        return;
    }

    // Retrieve decode start time from sourceFrameRefCon
    CFTimeInterval decodeStartTime = 0;
    if (sourceFrameRefCon) {
        decodeStartTime = *(CFTimeInterval *)sourceFrameRefCon;
        free(sourceFrameRefCon);
    }

    VideoFrame *frame = [[VideoFrame alloc] initWithPixelBuffer:imageBuffer];
    frame.decodeTime = CACurrentMediaTime() - decodeStartTime;
    frame.isHdr = self->_hdrEnabled;
    frame.is10Bit = (self->videoFormat & VIDEO_FORMAT_MASK_10BIT) != 0;

    // Determine color space from format
    if (self->videoFormat & VIDEO_FORMAT_MASK_H264) {
        frame.colorSpace = 709;
    } else {
        // HEVC and AV1 use BT.2020 for 10-bit, BT.709 for 8-bit
        frame.colorSpace = frame.is10Bit ? 2020 : 709;
    }

    [self->_frameQueue enqueue:frame];
}

#endif // !TARGET_OS_VISION

#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

- (void)updateAnnexBBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength
{
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);

    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }

    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }

    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

- (NSData*)getAv1CodecConfigurationBox:(NSData*)frameData  {
    AVIOContext* ioctx = NULL;
    int err;

    err = avio_open_dyn_buf(&ioctx);
    if (err < 0) {
        Log(LOG_E, @"avio_open_dyn_buf() failed: %d", err);
        return nil;
    }

    err = ff_isom_write_av1c(ioctx, (uint8_t*)frameData.bytes, (int)frameData.length, 1);
    if (err < 0) {
        Log(LOG_E, @"ff_isom_write_av1c() failed: %d", err);
    }

    uint8_t* av1cBuf = NULL;
    int av1cBufLen = avio_close_dyn_buf(ioctx, &av1cBuf);

    Log(LOG_I, @"av1C block is %d bytes", av1cBufLen);

    NSData* data = nil;
    if (err >= 0 && av1cBufLen > 0) {
        data = [NSData dataWithBytes:av1cBuf length:av1cBufLen];
    }

    av_free(av1cBuf);
    return data;
}

// Much of this logic comes from Chrome
- (CMVideoFormatDescriptionRef)createAV1FormatDescriptionForIDRFrame:(NSData*)frameData {
    NSMutableDictionary* extensions = [[NSMutableDictionary alloc] init];

    CodedBitstreamContext* cbsCtx = NULL;
    int err = ff_cbs_init(&cbsCtx, AV_CODEC_ID_AV1, NULL);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_init() failed: %d", err);
        return nil;
    }

    AVPacket avPacket = {};
    avPacket.data = (uint8_t*)frameData.bytes;
    avPacket.size = (int)frameData.length;

    CodedBitstreamFragment cbsFrag = {};
    err = ff_cbs_read_packet(cbsCtx, &cbsFrag, &avPacket);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_read_packet() failed: %d", err);
        ff_cbs_close(&cbsCtx);
        return nil;
    }

#define SET_CFSTR_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (__bridge NSString*)(value)
#define SET_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (value)

    SET_EXTENSION(kCMFormatDescriptionExtension_FormatName, @"av01");
    SET_EXTENSION(kCMFormatDescriptionExtension_Depth, @24);

    CodedBitstreamAV1Context* bitstreamCtx = (CodedBitstreamAV1Context*)cbsCtx->priv_data;
    AV1RawSequenceHeader* seqHeader = bitstreamCtx->sequence_header;
    if (seqHeader == NULL) {
        Log(LOG_E, @"AV1 sequence header not found in IDR frame!");
        ff_cbs_fragment_free(&cbsFrag);
        ff_cbs_close(&cbsCtx);
        return nil;
    }

    switch (seqHeader->color_config.color_primaries) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_709_2);
            break;
        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_SMPTE_C);
            break;
        case 9:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_2020);
            break;
        default:
            Log(LOG_W, @"Unsupported color_primaries value: %d", seqHeader->color_config.color_primaries);
            break;
    }

    switch (seqHeader->color_config.transfer_characteristics) {
        case 1:
        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_709_2);
            break;
        case 7:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_240M_1995);
            break;
        case 8:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_Linear);
            break;
        case 14:
        case 15:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2020);
            break;
        case 16:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ);
            break;
        case 17:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG);
            break;
        default:
            Log(LOG_W, @"Unsupported transfer_characteristics value: %d", seqHeader->color_config.transfer_characteristics);
            break;
    }

    switch (seqHeader->color_config.matrix_coefficients) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2);
            break;
        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4);
            break;
        case 7:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995);
            break;
        case 9:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_2020);
            break;
        default:
            Log(LOG_W, @"Unsupported matrix_coefficients value: %d", seqHeader->color_config.matrix_coefficients);
            break;
    }

    SET_EXTENSION(kCMFormatDescriptionExtension_FullRangeVideo, @(seqHeader->color_config.color_range == 1));
    SET_EXTENSION(kCMFormatDescriptionExtension_FieldCount, @(1));

    switch (seqHeader->color_config.chroma_sample_position) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_Left);
            break;
        case 2:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_TopLeft);
            break;
        default:
            Log(LOG_W, @"Unsupported chroma_sample_position value: %d", seqHeader->color_config.chroma_sample_position);
            break;
    }

    if (contentLightLevelInfo) {
        SET_EXTENSION(kCMFormatDescriptionExtension_ContentLightLevelInfo, contentLightLevelInfo);
    }
    if (masteringDisplayColorVolume) {
        SET_EXTENSION(kCMFormatDescriptionExtension_MasteringDisplayColorVolume, masteringDisplayColorVolume);
    }

    extensions[(__bridge NSString*)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] =
    @{
        @"av1C" : [self getAv1CodecConfigurationBox:frameData],
    };
    extensions[@"BitsPerComponent"] = @(bitstreamCtx->bit_depth);

#undef SET_EXTENSION
#undef SET_CFSTR_EXTENSION

    CMVideoFormatDescriptionRef fmtDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_AV1,
                                                     bitstreamCtx->frame_width, bitstreamCtx->frame_height,
                                                     (__bridge CFDictionaryRef)extensions,
                                                     &fmtDesc);
    if (status != noErr) {
        Log(LOG_E, @"Failed to create AV1 format description: %d", (int)status);
        fmtDesc = NULL;
    }

    ff_cbs_fragment_free(&cbsFrag);
    ff_cbs_close(&cbsCtx);
    return fmtDesc;
}

// This function must free data for bufferType == BUFFER_TYPE_PICDATA
- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du
{
    OSStatus status;
    CMBlockBufferRef dataBlockBuffer = NULL;
    CMBlockBufferRef frameBlockBuffer = NULL;
    CMSampleBufferRef sampleBuffer = NULL;

    // Construct a new format description object each time we receive an IDR frame
    if (du->frameType == FRAME_TYPE_IDR) {
        if (bufferType != BUFFER_TYPE_PICDATA) {
            if (bufferType == BUFFER_TYPE_VPS || bufferType == BUFFER_TYPE_SPS || bufferType == BUFFER_TYPE_PPS) {
                int startLen = data[2] == 0x01 ? 3 : 4;
                [parameterSetBuffers addObject:[NSData dataWithBytes:&data[startLen] length:length - startLen]];
            }
            return DR_OK;
        }

        if (formatDesc != NULL) {
            CFRelease(formatDesc);
            formatDesc = NULL;
        }

        if (videoFormat & VIDEO_FORMAT_MASK_H264) {
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new H264 format description");
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         &formatDesc);
            if (status != noErr) {
                Log(LOG_E, @"Failed to create H264 format description: %d", (int)status);
                formatDesc = NULL;
            }
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new HEVC format description");

            NSMutableDictionary* videoFormatParams = [[NSMutableDictionary alloc] init];
            if (contentLightLevelInfo) {
                [videoFormatParams setObject:contentLightLevelInfo forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ContentLightLevelInfo];
            }
            if (masteringDisplayColorVolume) {
                [videoFormatParams setObject:masteringDisplayColorVolume forKey:(__bridge NSString*)kCMFormatDescriptionExtension_MasteringDisplayColorVolume];
            }

            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         (__bridge CFDictionaryRef)videoFormatParams,
                                                                         &formatDesc);
            if (status != noErr) {
                Log(LOG_E, @"Failed to create HEVC format description: %d", (int)status);
                formatDesc = NULL;
            }
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
            NSData* fullFrameData = [NSData dataWithBytesNoCopy:data length:length freeWhenDone:NO];
            Log(LOG_I, @"Constructing new AV1 format description");
            formatDesc = [self createAV1FormatDescriptionForIDRFrame:fullFrameData];
        }
        else {
            abort();
        }

#if !TARGET_OS_VISION
        // Recreate the decompression session with the new format
        if (formatDesc) {
            if (![self createDecompressionSession]) {
                Log(LOG_E, @"Failed to create VTDecompressionSession");
                free(data);
                return DR_NEED_IDR;
            }
        }
#endif
    }

    if (formatDesc == NULL) {
        free(data);
        return DR_NEED_IDR;
    }

#if TARGET_OS_VISION
    // visionOS path: use AVSampleBufferVideoRenderer (existing behavior)
    if (_videoRenderer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        Log(LOG_E, @"Sample buffer video renderer failed: %@", _videoRenderer.error);
        if (formatDesc != nil) {
            CFRelease(formatDesc);
            formatDesc = nil;
        }
        free(data);
        return DR_NEED_IDR;
    }
#else
    // iOS/tvOS path: check decompression session
    if (!_decompressionSession) {
        free(data);
        return DR_NEED_IDR;
    }
#endif

    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DR_NEED_IDR;
    }

    // From now on, CMBlockBuffer owns the data pointer

    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DR_NEED_IDR;
    }

    // H.264 and HEVC formats require NAL prefix fixups from Annex B to length-delimited
    if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) {
        int lastOffset = -1;
        for (int i = 0; i < length - NALU_START_PREFIX_SIZE; i++) {
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                if (lastOffset != -1) {
                    [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
                }
                lastOffset = i;
            }
        }
        if (lastOffset != -1) {
            [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
        }
    }
    else {
        status = CMBlockBufferAppendBufferReference(frameBlockBuffer, dataBlockBuffer, 0, length, 0);
        if (status != noErr) {
            Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
            CFRelease(dataBlockBuffer);
            CFRelease(frameBlockBuffer);
            return DR_NEED_IDR;
        }
    }

    CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, CMTimeMake(du->presentationTimeMs, 1000), kCMTimeInvalid};

    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  formatDesc, 1, 1,
                                  &sampleTiming, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        return DR_NEED_IDR;
    }

#if TARGET_OS_VISION
    // visionOS: enqueue to AVSampleBufferVideoRenderer
    if ([_videoRenderer isReadyForMoreMediaData]) {
        [_videoRenderer enqueueSampleBuffer:sampleBuffer];
    }
#else
    // iOS/tvOS: decode via VTDecompressionSession → FrameQueue
    {
        // Pass decode start time through sourceFrameRefCon
        CFTimeInterval *decodeStart = malloc(sizeof(CFTimeInterval));
        *decodeStart = CACurrentMediaTime();

        VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
        VTDecodeInfoFlags infoFlags;

        OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(
            _decompressionSession,
            sampleBuffer,
            flags,
            decodeStart,  // sourceFrameRefCon — freed in callback
            &infoFlags);

        if (decodeStatus != noErr) {
            Log(LOG_E, @"VTDecompressionSessionDecodeFrame failed: %d", (int)decodeStatus);
            free(decodeStart);
        }
    }
#endif

    if (du->frameType == FRAME_TYPE_IDR) {
        [_callbacks videoContentShown];
    }

    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);

    return DR_OK;
}

- (void)setHdrMode:(BOOL)enabled {
    _hdrEnabled = enabled;

    SS_HDR_METADATA hdrMetadata;

    BOOL hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata);
    BOOL metadataChanged = NO;

    if (hasMetadata && hdrMetadata.displayPrimaries[0].x != 0 && hdrMetadata.maxDisplayLuminance != 0) {
        struct {
          vector_ushort2 primaries[3];
          vector_ushort2 white_point;
          uint32_t luminance_max;
          uint32_t luminance_min;
        } __attribute__((packed, aligned(4))) mdcv;

        mdcv.primaries[0].x = __builtin_bswap16(hdrMetadata.displayPrimaries[1].x);
        mdcv.primaries[0].y = __builtin_bswap16(hdrMetadata.displayPrimaries[1].y);
        mdcv.primaries[1].x = __builtin_bswap16(hdrMetadata.displayPrimaries[2].x);
        mdcv.primaries[1].y = __builtin_bswap16(hdrMetadata.displayPrimaries[2].y);
        mdcv.primaries[2].x = __builtin_bswap16(hdrMetadata.displayPrimaries[0].x);
        mdcv.primaries[2].y = __builtin_bswap16(hdrMetadata.displayPrimaries[0].y);

        mdcv.white_point.x = __builtin_bswap16(hdrMetadata.whitePoint.x);
        mdcv.white_point.y = __builtin_bswap16(hdrMetadata.whitePoint.y);

        mdcv.luminance_max = __builtin_bswap32((uint32_t)hdrMetadata.maxDisplayLuminance * 10000);
        mdcv.luminance_min = __builtin_bswap32(hdrMetadata.minDisplayLuminance);

        NSData* newMdcv = [NSData dataWithBytes:&mdcv length:sizeof(mdcv)];
        if (masteringDisplayColorVolume == nil || ![newMdcv isEqualToData:masteringDisplayColorVolume]) {
            masteringDisplayColorVolume = newMdcv;
            metadataChanged = YES;
        }
    }
    else if (masteringDisplayColorVolume != nil) {
        masteringDisplayColorVolume = nil;
        metadataChanged = YES;
    }

    if (hasMetadata && hdrMetadata.maxContentLightLevel != 0 && hdrMetadata.maxFrameAverageLightLevel != 0) {
        struct {
            uint16_t max_content_light_level;
            uint16_t max_frame_average_light_level;
        } __attribute__((packed, aligned(2))) cll;

        cll.max_content_light_level = __builtin_bswap16(hdrMetadata.maxContentLightLevel);
        cll.max_frame_average_light_level = __builtin_bswap16(hdrMetadata.maxFrameAverageLightLevel);

        NSData* newCll = [NSData dataWithBytes:&cll length:sizeof(cll)];
        if (contentLightLevelInfo == nil || ![newCll isEqualToData:contentLightLevelInfo]) {
            contentLightLevelInfo = newCll;
            metadataChanged = YES;
        }
    }
    else if (contentLightLevelInfo != nil) {
        contentLightLevelInfo = nil;
        metadataChanged = YES;
    }

    if (metadataChanged) {
        LiRequestIdrFrame();
    }
}

@end
