//
//  FrameQueue.h
//  Moonlight
//
//  Thread-safe frame queue with adaptive high water mark and drop policy.
//

#import <Foundation/Foundation.h>
#import "VideoFrame.h"

@interface FrameQueue : NSObject

- (instancetype)initWithCapacity:(int)capacity;

/// Enqueue a frame. If queue is full, drops the oldest frame.
/// Returns the number of frames dropped.
- (int)enqueue:(VideoFrame *)frame;

/// Dequeue the next frame. Returns nil if empty.
- (VideoFrame *)dequeue;

/// Blocks until a frame is available or the queue is shut down.
- (VideoFrame *)waitForFrame;

/// Signal that a frame has been enqueued (wakes waitForFrame).
- (void)signal;

/// Shutdown the queue, releasing any waiting threads.
- (void)shutdown;

/// Current number of frames in the queue.
- (int)count;

/// Total number of frames dropped since creation.
@property (nonatomic, readonly) int totalDroppedFrames;

@end
