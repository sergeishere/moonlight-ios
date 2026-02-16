import Foundation

@objc protocol StreamConnectionDelegate: AnyObject {
    func connectionStarted()
    func connectionTerminated(_ errorCode: Int32)
    func stageStarting(_ stageName: UnsafePointer<CChar>)
    func stageComplete(_ stageName: UnsafePointer<CChar>)
    func stageFailed(_ stageName: UnsafePointer<CChar>, withError errorCode: Int32, portTestFlags: Int32)
    func launchFailed(_ message: String)
    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16)
    func connectionStatusUpdate(_ status: Int32)
    func setHdrMode(_ enabled: Bool)
    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16)
    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)
    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8)
    func videoContentShown()
}
