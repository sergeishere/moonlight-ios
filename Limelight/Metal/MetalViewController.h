//
//  MetalViewController.h
//  Moonlight
//
//  Manages MetalView, initializes MetalVideoRenderer,
//  provides the FrameQueue for decoded frames, and manages
//  CADisplayLink for frame rate hints.
//

#import <UIKit/UIKit.h>
#import "FrameQueue.h"

@interface MetalViewController : UIViewController

/// The frame queue that the decoder should write frames to.
@property (nonatomic, strong, readonly) FrameQueue *frameQueue;

/// Initialize with streaming parameters.
- (instancetype)initWithFrame:(CGRect)frame
                    framerate:(int)framerate
                    enableHdr:(BOOL)enableHdr;

/// Configure the Metal layer for HDR output.
- (void)setHdrEnabled:(BOOL)enabled;

/// Stop rendering and clean up.
- (void)shutdown;

@end
