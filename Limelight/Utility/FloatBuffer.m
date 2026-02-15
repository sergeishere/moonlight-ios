//
//  FloatBuffer.m
//  Moonlight
//

#import "FloatBuffer.h"

@implementation FloatBuffer {
    float *_buffer;
    int _capacity;
    int _count;
    int _index;
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super init];
    _capacity = capacity;
    _buffer = (float *)calloc(capacity, sizeof(float));
    _count = 0;
    _index = 0;
    return self;
}

- (void)dealloc {
    free(_buffer);
}

- (void)addValue:(float)value {
    _buffer[_index] = value;
    _index = (_index + 1) % _capacity;
    if (_count < _capacity) {
        _count++;
    }
}

- (PlotMetrics)metrics {
    PlotMetrics m = PlotMetricsMake();
    for (int i = 0; i < _count; i++) {
        PlotMetricsUpdate(&m, _buffer[i]);
    }
    return m;
}

- (void)reset {
    _count = 0;
    _index = 0;
    memset(_buffer, 0, _capacity * sizeof(float));
}

@end
