//
//  AudioRenderer.m
//  Moonlight
//
//  AudioUnit (RemoteIO) renderer with Opus decoding and lock-free ring buffer.
//  Hot path (decode + render callback) is pure C — zero allocations, no ObjC dispatch.
//

#import "AudioRenderer.h"
#import "AudioRingBuffer.h"

#import <AudioToolbox/AudioToolbox.h>
#import <opus_multistream.h>

#if !TARGET_OS_VISION
#import <AVFoundation/AVAudioSession.h>
#endif

// Ring buffer capacity in frames (~40ms at 48kHz)
#define RING_BUFFER_FRAMES 2048

// Max decode buffer: 8 channels * 960 samples (20ms @ 48kHz) = 7680 floats
#define MAX_DECODE_SAMPLES (960 * 8)

static OpusMSDecoder *opusDecoder;
static AudioRingBuffer ringBuffer;
static AudioComponentInstance audioUnit;
static int channelCount;
static int samplesPerFrame;

// ─── Render callback (realtime thread — pure C) ──────────────────────────────

static OSStatus renderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    float *out = (float *)ioData->mBuffers[0].mData;
    uint32_t channels = ioData->mBuffers[0].mNumberChannels;
    uint32_t totalSamples = inNumberFrames * channels;

    uint32_t framesRead = AudioRingBuffer_Read(&ringBuffer, out, inNumberFrames, channels);

    // Fill remainder with silence on underrun
    if (framesRead < inNumberFrames) {
        uint32_t samplesRead = framesRead * channels;
        memset(out + samplesRead, 0, (totalSamples - samplesRead) * sizeof(float));
    }

    return noErr;
}

// ─── ArInit ──────────────────────────────────────────────────────────────────

int AudioRenderer_Init(int audioConfiguration,
                       const POPUS_MULTISTREAM_CONFIGURATION opusConfig,
                       void *context,
                       int arFlags)
{
    channelCount = opusConfig->channelCount;
    samplesPerFrame = opusConfig->samplesPerFrame;

    // ── AVAudioSession (iOS/tvOS only) ──
#if !TARGET_OS_VISION
    {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *error = nil;
        [session setPreferredSampleRate:(double)opusConfig->sampleRate error:&error];
        if (error) {
            fprintf(stderr, "AudioRenderer: setPreferredSampleRate failed: %s\n",
                    error.localizedDescription.UTF8String);
        }

        double bufferDuration = (double)opusConfig->samplesPerFrame / (double)opusConfig->sampleRate;
        [session setPreferredIOBufferDuration:bufferDuration error:&error];
        if (error) {
            fprintf(stderr, "AudioRenderer: setPreferredIOBufferDuration failed: %s\n",
                    error.localizedDescription.UTF8String);
        }
    }
#endif

    // ── Opus decoder ──
    int opusErr = 0;
    opusDecoder = opus_multistream_decoder_create(
        opusConfig->sampleRate,
        opusConfig->channelCount,
        opusConfig->streams,
        opusConfig->coupledStreams,
        opusConfig->mapping,
        &opusErr);

    if (opusErr != OPUS_OK || opusDecoder == NULL) {
        fprintf(stderr, "AudioRenderer: opus_multistream_decoder_create failed: %d\n", opusErr);
        return -1;
    }

    // ── Ring buffer ──
    if (AudioRingBuffer_Init(&ringBuffer, RING_BUFFER_FRAMES, channelCount) != 0) {
        fprintf(stderr, "AudioRenderer: AudioRingBuffer_Init failed\n");
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    // ── AudioUnit (RemoteIO) ──
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
#if TARGET_OS_VISION
        .componentSubType = kAudioUnitSubType_GenericOutput,
#else
        .componentSubType = kAudioUnitSubType_RemoteIO,
#endif
        .componentManufacturer = kAudioUnitManufacturer_Apple,
    };

    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    if (component == NULL) {
        fprintf(stderr, "AudioRenderer: AudioComponentFindNext failed\n");
        AudioRingBuffer_Destroy(&ringBuffer);
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    OSStatus status = AudioComponentInstanceNew(component, &audioUnit);
    if (status != noErr) {
        fprintf(stderr, "AudioRenderer: AudioComponentInstanceNew failed: %d\n", (int)status);
        AudioRingBuffer_Destroy(&ringBuffer);
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    // ASBD: interleaved float32 — matches opus_multistream_decode_float output directly
    AudioStreamBasicDescription asbd = {
        .mSampleRate       = (Float64)opusConfig->sampleRate,
        .mFormatID         = kAudioFormatLinearPCM,
        .mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        .mBytesPerPacket   = (UInt32)(sizeof(float) * opusConfig->channelCount),
        .mFramesPerPacket  = 1,
        .mBytesPerFrame    = (UInt32)(sizeof(float) * opusConfig->channelCount),
        .mChannelsPerFrame = (UInt32)opusConfig->channelCount,
        .mBitsPerChannel   = 32,
    };

    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0, // output bus
                                  &asbd,
                                  sizeof(asbd));
    if (status != noErr) {
        fprintf(stderr, "AudioRenderer: AudioUnitSetProperty StreamFormat failed: %d\n", (int)status);
        AudioComponentInstanceDispose(audioUnit);
        audioUnit = NULL;
        AudioRingBuffer_Destroy(&ringBuffer);
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    // Render callback
    AURenderCallbackStruct callbackStruct = {
        .inputProc = renderCallback,
        .inputProcRefCon = NULL,
    };

    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    if (status != noErr) {
        fprintf(stderr, "AudioRenderer: AudioUnitSetProperty RenderCallback failed: %d\n", (int)status);
        AudioComponentInstanceDispose(audioUnit);
        audioUnit = NULL;
        AudioRingBuffer_Destroy(&ringBuffer);
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    status = AudioUnitInitialize(audioUnit);
    if (status != noErr) {
        fprintf(stderr, "AudioRenderer: AudioUnitInitialize failed: %d\n", (int)status);
        AudioComponentInstanceDispose(audioUnit);
        audioUnit = NULL;
        AudioRingBuffer_Destroy(&ringBuffer);
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
        return -1;
    }

    return 0;
}

// ─── ArStart ─────────────────────────────────────────────────────────────────

void AudioRenderer_Start(void) {
    if (audioUnit != NULL) {
        OSStatus status = AudioOutputUnitStart(audioUnit);
        if (status != noErr) {
            fprintf(stderr, "AudioRenderer: AudioOutputUnitStart failed: %d\n", (int)status);
        }
    }
}

// ─── ArDecodeAndPlaySample (hot path — 0 heap allocations) ──────────────────

void AudioRenderer_DecodeAndPlaySample(char *sampleData, int sampleLength) {
    float decodeBuffer[MAX_DECODE_SAMPLES];

    int decodedFrames = opus_multistream_decode_float(
        opusDecoder,
        sampleData != NULL ? (const unsigned char *)sampleData : NULL,
        sampleData != NULL ? sampleLength : 0,
        decodeBuffer,
        samplesPerFrame,
        0);

    if (decodedFrames > 0) {
        AudioRingBuffer_Write(&ringBuffer, decodeBuffer, (uint32_t)decodedFrames, (uint32_t)channelCount);
    }
}

// ─── ArStop ──────────────────────────────────────────────────────────────────

void AudioRenderer_Stop(void) {
    if (audioUnit != NULL) {
        AudioOutputUnitStop(audioUnit);
    }
}

// ─── ArCleanup ───────────────────────────────────────────────────────────────

void AudioRenderer_Cleanup(void) {
    if (audioUnit != NULL) {
        AudioUnitUninitialize(audioUnit);
        AudioComponentInstanceDispose(audioUnit);
        audioUnit = NULL;
    }

    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }

    AudioRingBuffer_Destroy(&ringBuffer);
}
