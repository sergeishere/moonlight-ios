import Foundation
import GameController

final class Controller: @unchecked Sendable {
    struct TouchContext {
        var lastX: Float = 0
        var lastY: Float = 0
    }

    var gamepad: GCController?
    var playerIndex: Int32 = 0
    var lastButtonFlags: Int32 = 0
    var emulatingButtonFlags: Int32 = 0
    var supportedEmulationFlags: Int32 = 0
    var lastLeftTrigger: UInt8 = 0
    var lastRightTrigger: UInt8 = 0
    var lastLeftStickX: Int16 = 0
    var lastLeftStickY: Int16 = 0
    var lastRightStickX: Int16 = 0
    var lastRightStickY: Int16 = 0

    var primaryTouch = TouchContext()
    var secondaryTouch = TouchContext()

    var lowFreqMotor: HapticContext?
    var highFreqMotor: HapticContext?
    var leftTriggerMotor: HapticContext?
    var rightTriggerMotor: HapticContext?

    var accelTimer: Timer?
    var lastAccelSample = GCAcceleration()
    var gyroTimer: Timer?
    var lastGyroSample = GCRotationRate()

    var batteryTimer: Timer?
    var lastBatteryState: GCDeviceBattery.State = .unknown
    var lastBatteryLevel: Float = 0

    var reportedArrival = false
    weak var mergedWithController: Controller?
}
