//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Connection.h"

#if !TARGET_OS_VISION
#import "FrameQueue.h"
#endif

@interface StreamManager : NSOperation

@property (strong, nonatomic) Connection* connection;

#if TARGET_OS_VISION
- (id) initWithConfig:(StreamConfiguration*)config
            renderView:(UIView*)view
    sampleBufferVideoRenderer:(AVSampleBufferVideoRenderer*)renderer
       connectionCallbacks:(id<ConnectionCallbacks>)callback;
#else
- (id) initWithConfig:(StreamConfiguration*)config
            renderView:(UIView*)view
            frameQueue:(FrameQueue *)frameQueue
       connectionCallbacks:(id<ConnectionCallbacks>)callback;
#endif

- (void) stopStream;

- (NSString*) getStatsOverlayText;

@end
