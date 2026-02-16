//
//  VisionStreamViewController.h
//  Moonlight
//
//  Minimal streaming view controller for visionOS.
//  Uses AVSampleBufferDisplayLayer instead of Metal pipeline.
//

#include <TargetConditionals.h>

#if TARGET_OS_VISION

#import "ConnectionCallbacks.h"
#import "StreamConfiguration.h"
#import "ControllerSupport.h"

#import <UIKit/UIKit.h>

@interface VisionStreamViewController : UIViewController <ConnectionCallbacks, ControllerSupportDelegate>

@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, copy) void (^onDismiss)(void);

@end

#endif // TARGET_OS_VISION
