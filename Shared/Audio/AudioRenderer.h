//
//  AudioRenderer.h
//  Moonlight
//
//  AudioUnit (RemoteIO) based audio renderer with lock-free SPSC ring buffer.
//  Replaces AVAudioEngine-based AudioStreamHandler for lower latency.
//

#ifndef AudioRenderer_h
#define AudioRenderer_h

#include "Limelight.h"

// Audio callbacks matching moonlight-common-c AUDIO_RENDERER_CALLBACKS signatures.
int  AudioRenderer_Init(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int arFlags);
void AudioRenderer_Start(void);
void AudioRenderer_Stop(void);
void AudioRenderer_Cleanup(void);
void AudioRenderer_DecodeAndPlaySample(char* sampleData, int sampleLength);

#endif /* AudioRenderer_h */
