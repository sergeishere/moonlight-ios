//
//  TemporarySettings.m
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "TemporarySettings.h"

@implementation TemporarySettings

- (id) initFromUserDefaults {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        // Register defaults for first launch
        [defaults registerDefaults:@{
            @"bitrate": @10000,
            @"framerate": @60,
            @"height": @720,
            @"width": @1280,
            @"audioConfig": @2,
            @"onscreenControls": @1,
            @"optimizeGames": @YES,
            @"multiController": @YES,
            @"swapABXYButtons": @NO,
            @"playAudioOnPC": @NO,
            @"preferredCodec": @0,
            @"useFramePacing": @NO,
            @"enableHdr": @NO,
            @"btMouseSupport": @NO,
            @"absoluteTouchMode": @NO,
            @"statsOverlay": @NO,
        }];

        self.bitrate = @([defaults integerForKey:@"bitrate"]);
        self.framerate = @([defaults integerForKey:@"framerate"]);
        self.height = @([defaults integerForKey:@"height"]);
        self.width = @([defaults integerForKey:@"width"]);
        self.audioConfig = @([defaults integerForKey:@"audioConfig"]);
        self.onscreenControls = @([defaults integerForKey:@"onscreenControls"]);
        self.preferredCodec = (typeof(self.preferredCodec))[defaults integerForKey:@"preferredCodec"];
        self.useFramePacing = [defaults boolForKey:@"useFramePacing"];
        self.multiController = [defaults boolForKey:@"multiController"];
        self.swapABXYButtons = [defaults boolForKey:@"swapABXYButtons"];
        self.playAudioOnPC = [defaults boolForKey:@"playAudioOnPC"];
        self.optimizeGames = [defaults boolForKey:@"optimizeGames"];
        self.enableHdr = [defaults boolForKey:@"enableHdr"];
        self.btMouseSupport = [defaults boolForKey:@"btMouseSupport"];
        self.absoluteTouchMode = [defaults boolForKey:@"absoluteTouchMode"];
        self.statsOverlay = [defaults boolForKey:@"statsOverlay"];
        self.uniqueId = [defaults stringForKey:@"uniqueId"] ?: @"";
    }
    return self;
}

@end
