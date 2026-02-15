//
//  MetalView.h
//  Moonlight
//
//  UIView backed by CAMetalLayer. Runs a dedicated render thread
//  with tight loop: waitToRender → render.
//

#import <UIKit/UIKit.h>
#import "FrameQueue.h"

@class VideoFrame;

@protocol MetalViewDelegate <NSObject>
- (BOOL)waitToRenderOnLayer:(id)layer;
- (void)renderFrame:(VideoFrame *)frame;
@end

@interface MetalView : UIView

@property (nonatomic, weak) id<MetalViewDelegate> renderDelegate;
@property (nonatomic, strong) FrameQueue *frameQueue;

- (id)metalLayer;
- (void)startRenderLoop;
- (void)stopRenderLoop;

@end
