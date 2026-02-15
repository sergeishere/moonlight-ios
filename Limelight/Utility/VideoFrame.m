//
//  VideoFrame.m
//  Moonlight
//

#import "VideoFrame.h"

@implementation VideoFrame

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    self = [super init];
    if (self) {
        _pixelBuffer = pixelBuffer;
        if (pixelBuffer) {
            CVPixelBufferRetain(pixelBuffer);
        }
    }
    return self;
}

- (void)dealloc {
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
}

@end
