//
//  MetalVideoRenderer.h
//  Moonlight
//
//  Renders CVPixelBuffer frames to a CAMetalLayer via Metal.
//  Handles YUV→RGB conversion and HDR tone mapping.
//

#import <Foundation/Foundation.h>

@class VideoFrame;

@interface MetalVideoRenderer : NSObject

- (instancetype)initWithDevice:(id)device;

/// Acquire the next drawable from the layer. Blocks until available.
/// Returns YES if successful, NO if the layer is not ready.
- (BOOL)waitToRenderOnLayer:(id)layer;

/// Render the given frame to the previously acquired drawable.
- (void)renderFrame:(VideoFrame *)frame;

/// Clean up Metal resources.
- (void)shutdown;

@end
