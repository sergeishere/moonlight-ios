//
//  VisionStreamViewController.h
//  Moonlight
//
//  Minimal streaming view controller for visionOS.
//  Uses AVSampleBufferDisplayLayer instead of Metal pipeline.
//

#include <TargetConditionals.h>

#if TARGET_OS_VISION

#import "StreamConfiguration.h"

#import <UIKit/UIKit.h>

#define CONN_TEST_SERVER "ios.conntest.moonlight-stream.org"

@interface VisionStreamViewController : UIViewController

@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, copy) void (^onDismiss)(void);

@end

#endif // TARGET_OS_VISION
