//
//  VideoFrame.h
//  Moonlight
//
//  Wrapper around CVPixelBuffer with decode metadata.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

@interface VideoFrame : NSObject

@property (nonatomic) CVPixelBufferRef pixelBuffer;
@property (nonatomic) int frameNumber;
@property (nonatomic) CFTimeInterval decodeTime;
@property (nonatomic) CFTimeInterval presentationTime;
@property (nonatomic) BOOL isHdr;
@property (nonatomic) BOOL is10Bit;
@property (nonatomic) BOOL isFullRange;
@property (nonatomic) int colorSpace; // 601, 709, 2020

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end
