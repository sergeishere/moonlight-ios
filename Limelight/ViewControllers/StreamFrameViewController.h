//
//  StreamFrameViewController.h
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#include <TargetConditionals.h>

#if !TARGET_OS_VISION

#import "StreamConfiguration.h"
#import "StreamView.h"

#import <UIKit/UIKit.h>

#define CONN_TEST_SERVER "ios.conntest.moonlight-stream.org"

#if TARGET_OS_TV
@import GameController;

@interface StreamFrameViewController : GCEventViewController <UserInteractionDelegate, UIScrollViewDelegate>
#else
@interface StreamFrameViewController : UIViewController <UserInteractionDelegate, UIScrollViewDelegate>
#endif
@property (nonatomic) StreamConfiguration* streamConfig;
@property (nonatomic, copy) void (^onDismiss)(void);

-(void)updatePreferredDisplayMode:(BOOL)streamActive;

@end

#endif // !TARGET_OS_VISION
