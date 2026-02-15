//
//  DataManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "DataManager.h"

@implementation DataManager

- (id) init {
    self = [super init];
    return self;
}

- (void) updateUniqueId:(NSString*)uniqueId {
    [[NSUserDefaults standardUserDefaults] setObject:uniqueId forKey:@"uniqueId"];
}

- (NSString*) getUniqueId {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"uniqueId"] ?: @"";
}

- (void) saveSettingsWithBitrate:(NSInteger)bitrate
                       framerate:(NSInteger)framerate
                          height:(NSInteger)height
                           width:(NSInteger)width
                     audioConfig:(NSInteger)audioConfig
                onscreenControls:(NSInteger)onscreenControls
                   optimizeGames:(BOOL)optimizeGames
                 multiController:(BOOL)multiController
                 swapABXYButtons:(BOOL)swapABXYButtons
                       audioOnPC:(BOOL)audioOnPC
                  preferredCodec:(uint32_t)preferredCodec
                  useFramePacing:(BOOL)useFramePacing
                       enableHdr:(BOOL)enableHdr
                  btMouseSupport:(BOOL)btMouseSupport
               absoluteTouchMode:(BOOL)absoluteTouchMode
                    statsOverlay:(BOOL)statsOverlay {

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:bitrate forKey:@"bitrate"];
    [defaults setInteger:framerate forKey:@"framerate"];
    [defaults setInteger:height forKey:@"height"];
    [defaults setInteger:width forKey:@"width"];
    [defaults setInteger:audioConfig forKey:@"audioConfig"];
    [defaults setInteger:onscreenControls forKey:@"onscreenControls"];
    [defaults setBool:optimizeGames forKey:@"optimizeGames"];
    [defaults setBool:multiController forKey:@"multiController"];
    [defaults setBool:swapABXYButtons forKey:@"swapABXYButtons"];
    [defaults setBool:audioOnPC forKey:@"playAudioOnPC"];
    [defaults setInteger:preferredCodec forKey:@"preferredCodec"];
    [defaults setBool:useFramePacing forKey:@"useFramePacing"];
    [defaults setBool:enableHdr forKey:@"enableHdr"];
    [defaults setBool:btMouseSupport forKey:@"btMouseSupport"];
    [defaults setBool:absoluteTouchMode forKey:@"absoluteTouchMode"];
    [defaults setBool:statsOverlay forKey:@"statsOverlay"];
}

- (TemporarySettings*) getSettings {
    return [[TemporarySettings alloc] initFromUserDefaults];
}

@end
