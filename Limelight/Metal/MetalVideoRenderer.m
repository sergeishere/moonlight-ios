//
//  MetalVideoRenderer.m
//  Moonlight
//

#if !TARGET_OS_VISION

#import "MetalVideoRenderer.h"
#import "VideoFrame.h"
#import "Logger.h"
@import Metal;
@import MetalKit;
@import QuartzCore;

// Must match the struct in Shaders.metal
typedef struct {
    int colorSpace;
    int isFullRange;
    int is10Bit;
} FragmentParams;

// Must match the struct in Shaders-Linear.metal
typedef struct {
    int colorSpace;
    int isFullRange;
    int is10Bit;
    float maxDisplayNits;
} LinearFragmentParams;

@implementation MetalVideoRenderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineSDR;
    id<MTLRenderPipelineState> _pipelineHDR;
    CVMetalTextureCacheRef _textureCache;
    id<CAMetalDrawable> _currentDrawable;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _commandQueue = [device newCommandQueue];

        [self setupPipelines];
        [self setupTextureCache];
    }
    return self;
}

- (void)setupPipelines {
    NSError *error = nil;
    id<MTLLibrary> library = [_device newDefaultLibrary];
    if (!library) {
        Log(LOG_E, @"Failed to create Metal default library");
        return;
    }

    // SDR pipeline
    {
        id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexPassthrough"];
        id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentYUVtoRGB"];

        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = vertexFunc;
        desc.fragmentFunction = fragmentFunc;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

        _pipelineSDR = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (error) {
            Log(LOG_E, @"Failed to create SDR pipeline: %@", error);
        }
    }

    // HDR pipeline
    {
        id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexPassthroughLinear"];
        id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentYUVtoRGBLinear"];

        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = vertexFunc;
        desc.fragmentFunction = fragmentFunc;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;

        _pipelineHDR = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (error) {
            Log(LOG_E, @"Failed to create HDR pipeline: %@", error);
        }
    }
}

- (void)setupTextureCache {
    CVReturn result = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL,
                                                 _device, NULL, &_textureCache);
    if (result != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create CVMetalTextureCache: %d", result);
    }
}

- (BOOL)waitToRenderOnLayer:(CAMetalLayer *)layer {
    if (!layer) return NO;

    _currentDrawable = [layer nextDrawable];
    return _currentDrawable != nil;
}

- (void)renderFrame:(VideoFrame *)frame {
    if (!_currentDrawable || !frame || !frame.pixelBuffer) return;

    CVPixelBufferRef pixelBuffer = frame.pixelBuffer;
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);

    // Get pixel format to determine plane formats
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    BOOL is10Bit = (pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                    pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange);
    BOOL isBiPlanar = CVPixelBufferGetPlaneCount(pixelBuffer) == 2;

    if (!isBiPlanar) {
        Log(LOG_E, @"Unsupported pixel buffer format: not biplanar");
        return;
    }

    // Create Metal textures from CVPixelBuffer planes
    CVMetalTextureRef lumaTextureRef = NULL;
    CVMetalTextureRef chromaTextureRef = NULL;

    MTLPixelFormat lumaFormat = is10Bit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm;
    MTLPixelFormat chromaFormat = is10Bit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm;

    size_t lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    CVReturn result = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, _textureCache, pixelBuffer,
        NULL, lumaFormat, lumaWidth, lumaHeight, 0, &lumaTextureRef);
    if (result != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create luma texture: %d", result);
        return;
    }

    size_t chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    size_t chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    result = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, _textureCache, pixelBuffer,
        NULL, chromaFormat, chromaWidth, chromaHeight, 1, &chromaTextureRef);
    if (result != kCVReturnSuccess) {
        Log(LOG_E, @"Failed to create chroma texture: %d", result);
        CFRelease(lumaTextureRef);
        return;
    }

    id<MTLTexture> lumaTexture = CVMetalTextureGetTexture(lumaTextureRef);
    id<MTLTexture> chromaTexture = CVMetalTextureGetTexture(chromaTextureRef);

    // Select pipeline and set params
    BOOL useHDR = frame.isHdr;
    id<MTLRenderPipelineState> pipeline = useHDR ? _pipelineHDR : _pipelineSDR;

    MTLRenderPassDescriptor *renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPass.colorAttachments[0].texture = _currentDrawable.texture;
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];

    // Calculate aspect-ratio-preserving viewport
    CGFloat drawableW = _currentDrawable.texture.width;
    CGFloat drawableH = _currentDrawable.texture.height;
    CGFloat videoAspect = (CGFloat)width / (CGFloat)height;
    CGFloat drawableAspect = drawableW / drawableH;

    CGFloat vpX, vpY, vpW, vpH;
    if (videoAspect > drawableAspect) {
        // Video is wider — letterbox top/bottom
        vpW = drawableW;
        vpH = drawableW / videoAspect;
        vpX = 0;
        vpY = (drawableH - vpH) / 2.0;
    } else {
        // Video is taller — pillarbox left/right
        vpH = drawableH;
        vpW = drawableH * videoAspect;
        vpX = (drawableW - vpW) / 2.0;
        vpY = 0;
    }

    MTLViewport viewport = { vpX, vpY, vpW, vpH, 0.0, 1.0 };
    [encoder setViewport:viewport];

    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:lumaTexture atIndex:0];
    [encoder setFragmentTexture:chromaTexture atIndex:1];

    if (useHDR) {
        LinearFragmentParams params;
        params.colorSpace = frame.colorSpace;
        params.isFullRange = frame.isFullRange ? 1 : 0;
        params.is10Bit = is10Bit ? 1 : 0;
        params.maxDisplayNits = 1000.0f;
        [encoder setFragmentBytes:&params length:sizeof(params) atIndex:0];
    } else {
        FragmentParams params;
        params.colorSpace = frame.colorSpace;
        params.isFullRange = frame.isFullRange ? 1 : 0;
        params.is10Bit = is10Bit ? 1 : 0;
        [encoder setFragmentBytes:&params length:sizeof(params) atIndex:0];
    }

    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];

    [commandBuffer presentDrawable:_currentDrawable];
    [commandBuffer commit];

    _currentDrawable = nil;

    // Clean up texture references
    CFRelease(lumaTextureRef);
    CFRelease(chromaTextureRef);
}

- (void)shutdown {
    if (_textureCache) {
        CVMetalTextureCacheFlush(_textureCache, 0);
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    _commandQueue = nil;
    _currentDrawable = nil;
}

@end

#endif // !TARGET_OS_VISION
