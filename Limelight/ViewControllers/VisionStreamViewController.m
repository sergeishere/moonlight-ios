//
//  VisionStreamViewController.m
//  Moonlight
//
//  Minimal streaming view controller for visionOS.
//  Uses AVSampleBufferDisplayLayer instead of Metal pipeline.
//

#if TARGET_OS_VISION

#import "VisionStreamViewController.h"
#import "Utils.h"

#if __has_include("Moonlight_Vision-Swift.h")
#import "Moonlight_Vision-Swift.h"
#elif __has_include("Moonlight-Swift.h")
#import "Moonlight-Swift.h"
#endif

@import AVFoundation;

#include <Limelight.h>

@interface VisionStreamViewController () <StreamConnectionDelegate>
@end

@implementation VisionStreamViewController {
    StreamSession *_streamSession;
    ControllerSupport *_controllerSupport;
    AVSampleBufferDisplayLayer *_displayLayer;
    UIActivityIndicatorView *_spinner;
    UILabel *_stageLabel;
}

// MARK: - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;

    // AVSampleBufferDisplayLayer for video output
    _displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    _displayLayer.frame = self.view.bounds;
    _displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:_displayLayer];

    // Loading UI
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = UIColor.whiteColor;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];
    [_spinner startAnimating];

    _stageLabel = [[UILabel alloc] init];
    _stageLabel.text = [NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName];
    _stageLabel.textColor = UIColor.whiteColor;
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_stageLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [_stageLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_stageLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:16],
    ]];

    // Controller support
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];

    // Get renderer from display layer
    AVSampleBufferVideoRenderer *renderer = _displayLayer.sampleBufferRenderer;

    // Create and start stream session
    _streamSession = [[StreamSession alloc] initWithConfig:self.streamConfig
                                             videoRenderer:renderer
                                                  delegate:self];
    [_streamSession start];

    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _displayLayer.frame = self.view.bounds;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (parent == nil) {
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamSession stop];
    }
}

// MARK: - Navigation

- (void)returnToMainFrame {
    if (self.onDismiss) {
        self.onDismiss();
    }
}

// MARK: - StreamConnectionDelegate

- (void)connectionStarted {
    Log(LOG_I, @"Connection started (visionOS)");
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_stageLabel.hidden = YES;
        [self->_controllerSupport connectionEstablished];
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);

    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;

        if (errorCode == ML_ERROR_GRACEFUL_TERMINATION) {
            [self returnToMainFrame];
            return;
        }

        NSString *title;
        NSString *message;

        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network.";
        } else {
            switch (errorCode) {
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    break;
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                default: {
                    NSString *errorString = (abs(errorCode) > 1000)
                        ? [NSString stringWithFormat:@"%08X", (uint32_t)errorCode]
                        : [NSString stringWithFormat:@"%d", errorCode];
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat:@"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });

    [_streamSession stop];
}

- (void)stageStarting:(const char *)stageName {
    Log(LOG_I, @"Starting %s (visionOS)", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString *titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
    });
}

- (void)stageComplete:(const char *)stageName {
}

- (void)stageFailed:(const char *)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d (visionOS)", stageName, errorCode);

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;

        NSString *message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });

    [_streamSession stop];
}

- (void)launchFailed:(NSString *)message {
    Log(LOG_I, @"Launch failed: %@ (visionOS)", message);

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].idleTimerDisabled = NO;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void)rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void)setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void)setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    // No overlay UI on visionOS for now
}

- (void)setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s (visionOS)", enabled ? "active" : "inactive");
}

- (void)videoContentShown {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_spinner stopAnimating];
    });
}

// MARK: - ControllerSupportDelegate

- (void)gamepadPresenceChanged {
}

- (void)mousePresenceChanged {
}

- (void)streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit (visionOS)");
    [self returnToMainFrame];
}

@end

#endif // TARGET_OS_VISION
