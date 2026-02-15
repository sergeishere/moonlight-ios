//
//  VideoDecoderRenderer.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/18/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "ConnectionCallbacks.h"
#import "FrameQueue.h"
#import "Plot.h"

#include "Limelight.h"

@interface VideoDecoderRenderer : NSObject

#if TARGET_OS_VISION
- (id)initWithCallbacks:(id<ConnectionCallbacks>)callbacks
    sampleBufferVideoRenderer:(AVSampleBufferVideoRenderer*)renderer
            streamAspectRatio:(float)aspectRatio
               useFramePacing:(BOOL)useFramePacing;
#else
- (id)initWithCallbacks:(id<ConnectionCallbacks>)callbacks
             frameQueue:(FrameQueue *)frameQueue
      streamAspectRatio:(float)aspectRatio;
#endif

- (void)setupWithVideoFormat:(int)videoFormat width:(int)videoWidth height:(int)videoHeight frameRate:(int)frameRate;
- (void)start;
- (void)stop;
- (void)setHdrMode:(BOOL)enabled;

- (int)submitDecodeBuffer:(unsigned char *)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du;

@end
