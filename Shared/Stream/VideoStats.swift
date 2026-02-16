import Foundation

struct VideoStats {
    var startTime: CFTimeInterval = 0
    var endTime: CFTimeInterval = 0
    var totalFrames: Int32 = 0
    var receivedFrames: Int32 = 0
    var networkDroppedFrames: Int32 = 0
    var totalHostProcessingLatency: Int32 = 0
    var framesWithHostProcessingLatency: Int32 = 0
    var maxHostProcessingLatency: Int32 = 0
    var minHostProcessingLatency: Int32 = 0
}
