//
//  FloatBuffer.h
//  Moonlight
//
//  Ring buffer of float values for streaming metrics.
//

#import <Foundation/Foundation.h>
#import "Plot.h"

@interface FloatBuffer : NSObject

- (instancetype)initWithCapacity:(int)capacity;
- (void)addValue:(float)value;
- (PlotMetrics)metrics;
- (void)reset;

@end
