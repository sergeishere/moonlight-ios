//
//  MetalViewController.m
//  Moonlight
//

#if !TARGET_OS_VISION

#import "MetalViewController.h"
#import "MetalView.h"
#import "MetalVideoRenderer.h"
#import "VideoFrame.h"
#import "MetalConfig.h"
@import Metal;
@import QuartzCore;

@interface MetalViewController () <MetalViewDelegate>
@end

@implementation MetalViewController {
    MetalView *_metalView;
    MetalVideoRenderer *_renderer;
    CADisplayLink *_displayLink;
    int _framerate;
    BOOL _enableHdr;
    CGRect _initialFrame;
}

- (instancetype)initWithFrame:(CGRect)frame
                    framerate:(int)framerate
                    enableHdr:(BOOL)enableHdr {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialFrame = frame;
        _framerate = framerate;
        _enableHdr = enableHdr;
        _frameQueue = [[FrameQueue alloc] initWithCapacity:FRAME_QUEUE_CAPACITY];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _metalView = [[MetalView alloc] initWithFrame:_initialFrame];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _metalView.renderDelegate = self;
    _metalView.frameQueue = _frameQueue;

    if (_enableHdr) {
        [self configureLayerForHDR:YES];
    }

    self.view = _metalView;

    CAMetalLayer *metalLayer = (CAMetalLayer *)[_metalView metalLayer];
    _renderer = [[MetalVideoRenderer alloc] initWithDevice:metalLayer.device];

    // Set up CADisplayLink for frame rate hinting
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
    if (@available(iOS 15.0, tvOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(_framerate, _framerate, _framerate);
    } else {
        _displayLink.preferredFramesPerSecond = _framerate;
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

    [_metalView startRenderLoop];
}

- (void)displayLinkFired:(CADisplayLink *)sender {
    // CADisplayLink keeps the display at the requested frame rate.
}

- (void)configureLayerForHDR:(BOOL)enabled {
    CAMetalLayer *layer = (CAMetalLayer *)[_metalView metalLayer];
    if (enabled) {
        layer.pixelFormat = MTLPixelFormatRGBA16Float;
        layer.wantsExtendedDynamicRangeContent = YES;
        if (@available(iOS 16.0, tvOS 16.0, *)) {
            layer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        }
    } else {
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.wantsExtendedDynamicRangeContent = NO;
    }
}

- (void)setHdrEnabled:(BOOL)enabled {
    _enableHdr = enabled;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureLayerForHDR:enabled];
    });
}

#pragma mark - MetalViewDelegate

- (BOOL)waitToRenderOnLayer:(id)layer {
    return [_renderer waitToRenderOnLayer:layer];
}

- (void)renderFrame:(VideoFrame *)frame {
    [_renderer renderFrame:frame];
}

#pragma mark - Cleanup

- (void)shutdown {
    [_displayLink invalidate];
    _displayLink = nil;
    [_metalView stopRenderLoop];
    [_renderer shutdown];
}

- (void)dealloc {
    [self shutdown];
}

@end

#endif // !TARGET_OS_VISION
