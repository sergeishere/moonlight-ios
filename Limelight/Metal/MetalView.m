//
//  MetalView.m
//  Moonlight
//

#if !TARGET_OS_VISION

#import "MetalView.h"
#import "VideoFrame.h"
#import "Logger.h"
@import Metal;
@import QuartzCore;
#include <pthread.h>

@implementation MetalView {
    NSThread *_renderThread;
    BOOL _running;
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (id)metalLayer {
    return (CAMetalLayer *)self.layer;
}

- (CAMetalLayer *)_metalLayer {
    return (CAMetalLayer *)self.layer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CAMetalLayer *layer = [self _metalLayer];
        self.backgroundColor = [UIColor blackColor];
        layer.device = MTLCreateSystemDefaultDevice();
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
        layer.presentsWithTransaction = NO;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat scale = self.window.screen.nativeScale;
    [self _metalLayer].drawableSize = CGSizeMake(
        self.bounds.size.width * scale,
        self.bounds.size.height * scale
    );
}

- (void)startRenderLoop {
    if (_running) return;

    _running = YES;
    _renderThread = [[NSThread alloc] initWithTarget:self selector:@selector(renderLoop) object:nil];
    _renderThread.name = @"MetalRenderThread";
    _renderThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_renderThread start];
}

- (void)stopRenderLoop {
    _running = NO;
    [_frameQueue shutdown];
}

- (void)renderLoop {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

    Log(LOG_I, @"Metal render thread started");

    while (_running) {
        @autoreleasepool {
            if (![self.renderDelegate waitToRenderOnLayer:[self _metalLayer]]) {
                if (!_running) break;
                [NSThread sleepForTimeInterval:0.001];
                continue;
            }

            VideoFrame *frame = [_frameQueue waitForFrame];
            if (!frame) {
                if (!_running) break;
                continue;
            }

            [self.renderDelegate renderFrame:frame];
        }
    }

    Log(LOG_I, @"Metal render thread exited");
}

@end

#endif // !TARGET_OS_VISION
