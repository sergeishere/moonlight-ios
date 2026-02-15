//
//  MetalConfig.h
//  Moonlight
//
//  Configuration and logging macros for Metal video pipeline.
//

#ifndef MetalConfig_h
#define MetalConfig_h

#import "Logger.h"

#define LOG_I LOG_I
#define LOG_E LOG_E
#define LOG_W LOG_W

// Maximum frames in the decode queue before dropping
#define FRAME_QUEUE_CAPACITY 3

#endif /* MetalConfig_h */
