import Foundation
import GameController

@objc final class Controller: NSObject, @unchecked Sendable {
    struct TouchContext {
        var lastX: Float = 0
        var lastY: Float = 0
    }

    @objc var gamepad: GCController?
    @objc var playerIndex: Int32 = 0
    @objc var lastButtonFlags: Int32 = 0
    @objc var emulatingButtonFlags: Int32 = 0
    @objc var supportedEmulationFlags: Int32 = 0
    @objc var lastLeftTrigger: UInt8 = 0
    @objc var lastRightTrigger: UInt8 = 0
    @objc var lastLeftStickX: Int16 = 0
    @objc var lastLeftStickY: Int16 = 0
    @objc var lastRightStickX: Int16 = 0
    @objc var lastRightStickY: Int16 = 0

    var primaryTouch = TouchContext()
    var secondaryTouch = TouchContext()

    @objc var lowFreqMotor: HapticContext?
    @objc var highFreqMotor: HapticContext?
    @objc var leftTriggerMotor: HapticContext?
    @objc var rightTriggerMotor: HapticContext?

    @objc var accelTimer: Timer?
    var lastAccelSample = GCAcceleration()
    @objc var gyroTimer: Timer?
    var lastGyroSample = GCRotationRate()

    @objc var batteryTimer: Timer?
    @objc var lastBatteryState: GCDeviceBattery.State = .unknown
    @objc var lastBatteryLevel: Float = 0

    @objc var reportedArrival = false
    @objc weak var mergedWithController: Controller?
}
