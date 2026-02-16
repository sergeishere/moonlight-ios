//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#if __has_include("Moonlight-Swift.h")
#import "Moonlight-Swift.h"
#elif __has_include("Moonlight_TV-Swift.h")
#import "Moonlight_TV-Swift.h"
#elif __has_include("Moonlight_Vision-Swift.h")
#import "Moonlight_Vision-Swift.h"
#endif
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>

@implementation StreamManager {
    StreamConfiguration* _config;
    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;

#if TARGET_OS_VISION
    AVSampleBufferVideoRenderer* _videoRenderer;
#else
    FrameQueue* _frameQueue;
#endif
}

#if TARGET_OS_VISION

- (id) initWithConfig:(StreamConfiguration*)config
            renderView:(UIView*)view
    sampleBufferVideoRenderer:(AVSampleBufferVideoRenderer*)renderer
       connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _videoRenderer = renderer;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

#else

- (id) initWithConfig:(StreamConfiguration*)config
            renderView:(UIView*)view
            frameQueue:(FrameQueue *)frameQueue
       connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _frameQueue = frameQueue;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

#endif

- (void)main {
    [CryptoManager generateKeyPairUsingSSL];

    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];

    // Skip serverInfo request if app version was pre-filled from host discovery
    if (_config.appVersion == nil) {
        ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                           fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
        NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
        NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
        NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
        NSString* serverState = [serverInfoResp getStringTag:@"state"];
        if (![serverInfoResp isStatusOk]) {
            [_callbacks launchFailed:serverInfoResp.statusMessage];
            return;
        }
        else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
            [_callbacks launchFailed:@"Failed to connect to PC"];
            return;
        }

        if (![pairStatus isEqualToString:@"1"]) {
            [_callbacks launchFailed:@"Device not paired to PC"];
            return;
        }

        _config.appVersion = appversion;
        _config.gfeVersion = gfeVersion;
        _config.isResume = [serverState hasSuffix:@"_SERVER_BUSY"];
    }

    NSString* sessionUrl;
    if (_config.isResume) {
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }

    _config.rtspSessionUrl = sessionUrl;

    dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_VISION
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc]
            initWithCallbacks:self->_callbacks
            sampleBufferVideoRenderer:self->_videoRenderer
            streamAspectRatio:(float)self->_config.width / (float)self->_config.height
            useFramePacing:self->_config.useFramePacing];
#else
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc]
            initWithCallbacks:self->_callbacks
                   frameQueue:self->_frameQueue
            streamAspectRatio:(float)self->_config.width / (float)self->_config.height];
#endif

        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    [_connection terminate];
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }

    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }

    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;

    if (!_connection) {
        return nil;
    }

    if (![_connection getVideoStats:&stats]) {
        return nil;
    }

    uint32_t rtt, variance;
    NSString* latencyString;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        latencyString = [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance];
    }
    else {
        latencyString = @"N/A";
    }

    NSString* hostProcessingString;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingString = [NSString stringWithFormat:@"\nHost processing latency min/max/avg: %.1f/%.1f/%.1f ms",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
    }
    else {
        hostProcessingString = @"";
    }

    float interval = stats.endTime - stats.startTime;
    return [NSString stringWithFormat:@"Video stream: %dx%d %.2f FPS (Codec: %@)\nFrames dropped by your network connection: %.2f%%\nAverage network latency: %@%@",
            _config.width,
            _config.height,
            stats.totalFrames / interval,
            [_connection getActiveCodecName],
            stats.networkDroppedFrames / interval,
            latencyString,
            hostProcessingString];
}

@end
