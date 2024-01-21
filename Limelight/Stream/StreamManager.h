//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Connection.h"

@interface StreamManager : NSOperation

@property (strong, nonatomic) Connection* connection;

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view sampleBufferVideoRenderer:(AVSampleBufferVideoRenderer*)renderer connectionCallbacks:(id<ConnectionCallbacks>)callback;

- (void) stopStream;

- (NSString*) getStatsOverlayText;

@end
