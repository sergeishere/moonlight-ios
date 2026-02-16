//
//  AV1FormatHelper.h
//  Moonlight
//
//  ObjC helper for AV1 format description creation.
//  Uses FFmpeg C structs (CodedBitstreamContext, CodedBitstreamAV1Context)
//  which cannot be used from Swift.
//

@import CoreMedia;
#import <Foundation/Foundation.h>

@interface AV1FormatHelper : NSObject

+ (CMVideoFormatDescriptionRef _Nullable)createFormatDescriptionForIDRFrame:(NSData *)frameData
                                                      contentLightLevelInfo:(NSData * _Nullable)contentLightLevelInfo
                                                masteringDisplayColorVolume:(NSData * _Nullable)masteringDisplayColorVolume
    CF_RETURNS_RETAINED;

@end
