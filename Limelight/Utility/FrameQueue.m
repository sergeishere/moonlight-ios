//
//  FrameQueue.m
//  Moonlight
//

#import "FrameQueue.h"

@implementation FrameQueue {
    NSMutableArray<VideoFrame *> *_queue;
    int _capacity;
    NSCondition *_condition;
    BOOL _shuttingDown;
    int _totalDroppedFrames;
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _queue = [[NSMutableArray alloc] initWithCapacity:capacity];
        _condition = [[NSCondition alloc] init];
        _shuttingDown = NO;
        _totalDroppedFrames = 0;
    }
    return self;
}

- (int)enqueue:(VideoFrame *)frame {
    int dropped = 0;

    [_condition lock];

    // Drop oldest frames if at capacity
    while (_queue.count >= _capacity) {
        [_queue removeObjectAtIndex:0];
        dropped++;
        _totalDroppedFrames++;
    }

    [_queue addObject:frame];
    [_condition signal];
    [_condition unlock];

    return dropped;
}

- (VideoFrame *)dequeue {
    VideoFrame *frame = nil;

    [_condition lock];
    if (_queue.count > 0) {
        frame = _queue[0];
        [_queue removeObjectAtIndex:0];
    }
    [_condition unlock];

    return frame;
}

- (VideoFrame *)waitForFrame {
    [_condition lock];
    while (_queue.count == 0 && !_shuttingDown) {
        [_condition wait];
    }

    VideoFrame *frame = nil;
    if (_queue.count > 0) {
        frame = _queue[0];
        [_queue removeObjectAtIndex:0];
    }
    [_condition unlock];

    return frame;
}

- (void)signal {
    [_condition lock];
    [_condition signal];
    [_condition unlock];
}

- (void)shutdown {
    [_condition lock];
    _shuttingDown = YES;
    [_condition broadcast];
    [_condition unlock];
}

- (int)count {
    [_condition lock];
    int c = (int)_queue.count;
    [_condition unlock];
    return c;
}

- (int)totalDroppedFrames {
    return _totalDroppedFrames;
}

@end
