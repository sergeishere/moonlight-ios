import Foundation
import GameController
import os

private let EMULATING_SELECT: Int32 = 0x1
private let EMULATING_SPECIAL: Int32 = 0x2
private let MOUSE_SPEED_DIVISOR: Float = 1.25

protocol ControllerSupportDelegate: AnyObject {
    func gamepadPresenceChanged()
    func mousePresenceChanged()
    func streamExitRequested()
}

@objc final class ControllerSupport: NSObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "Moonlight", category: "ControllerSupport")

    private let controllerStreamLock = NSLock()
    private var controllers = [Int: Controller]()
    private weak var delegate: (any ControllerSupportDelegate)?

    private var accumulatedDeltaX: Float = 0
    private var accumulatedDeltaY: Float = 0
    private var accumulatedScrollX: Float = 0
    private var accumulatedScrollY: Float = 0

    private var osc: OnScreenControls?
    private var oscController: Controller
    private var oscEnabled: Bool
    private var controllerNumbers: UInt8 = 0
    private let multiController: Bool
    private let swapABXYButtons: Bool

    private var controllerConnectObserver: (any NSObjectProtocol)?
    private var controllerDisconnectObserver: (any NSObjectProtocol)?
    private var mouseConnectObserver: (any NSObjectProtocol)?
    private var mouseDisconnectObserver: (any NSObjectProtocol)?
    private var keyboardConnectObserver: (any NSObjectProtocol)?
    private var keyboardDisconnectObserver: (any NSObjectProtocol)?

    init(config streamConfig: StreamConfiguration, delegate: any ControllerSupportDelegate) {
        self.multiController = streamConfig.multiController
        self.swapABXYButtons = streamConfig.swapABXYButtons
        self.delegate = delegate

        oscController = Controller()
        oscController.playerIndex = 0
        oscEnabled = OnScreenControlsLevel(rawValue: Int(streamConfig.onscreenControls)) != .off

        super.init()

        Self.logger.info("Number of supported controllers connected: \(Self.getGamepadCount())")
        Self.logger.info("Multi-controller: \(self.multiController)")

        for controller in GCController.controllers() {
            if Self.isSupportedGamepad(controller) {
                assignController(controller)
                registerControllerCallbacks(controller)
            }
        }

        for mouse in GCMouse.mice() {
            registerMouseCallbacks(mouse)
        }

        controllerConnectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            Self.logger.info("Controller connected!")

            guard Self.isSupportedGamepad(controller) else { return }

            if let limeController = self.assignController(controller) {
                self.registerControllerCallbacks(controller)
                self.reportControllerArrival(limeController)
                self.updateAutoOnScreenControlMode()
                self.delegate?.gamepadPresenceChanged()
            }
        }

        controllerDisconnectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController else { return }
            Self.logger.info("Controller disconnected!")

            guard Self.isSupportedGamepad(controller) else { return }

            self.unregisterControllerCallbacks(controller)
            self.controllerNumbers &= ~(1 << controller.playerIndex.rawValue)
            Self.logger.info("Unassigning controller index: \(controller.playerIndex.rawValue)")

            if let limeController = self.controllers[Int(controller.playerIndex.rawValue)] {
                self.cleanupControllerHaptics(limeController)
                self.cleanupControllerMotion(limeController)
                self.cleanupControllerBattery(limeController)

                if let merged = limeController.mergedWithController {
                    assert(merged.mergedWithController === limeController)
                    merged.mergedWithController = nil
                }

                self.updateFinished(limeController)
                self.controllers.removeValue(forKey: Int(controller.playerIndex.rawValue))
                self.updateAutoOnScreenControlMode()
                self.delegate?.gamepadPresenceChanged()
            }
        }

        mouseConnectObserver = NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let mouse = note.object as? GCMouse else { return }
            Self.logger.info("Mouse connected!")
            self.registerMouseCallbacks(mouse)
            self.updateAutoOnScreenControlMode()
            self.delegate?.mousePresenceChanged()
        }

        mouseDisconnectObserver = NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let mouse = note.object as? GCMouse else { return }
            Self.logger.info("Mouse disconnected!")
            self.unregisterMouseCallbacks(mouse)
            self.updateAutoOnScreenControlMode()
            self.delegate?.mousePresenceChanged()
        }

        keyboardConnectObserver = NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            Self.logger.info("Keyboard connected!")
            self?.updateAutoOnScreenControlMode()
        }

        keyboardDisconnectObserver = NotificationCenter.default.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Self.logger.info("Keyboard disconnected!")
            self?.updateAutoOnScreenControlMode()
        }
    }

    // MARK: - Public API

    @objc func connectionEstablished() {
        for controller in controllers.values {
            reportControllerArrival(controller)
        }
    }

    @objc func cleanup() {
        if let o = controllerConnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = controllerDisconnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = mouseConnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = mouseDisconnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = keyboardConnectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = keyboardDisconnectObserver { NotificationCenter.default.removeObserver(o) }

        controllerConnectObserver = nil
        controllerDisconnectObserver = nil
        mouseConnectObserver = nil
        mouseDisconnectObserver = nil
        keyboardConnectObserver = nil
        keyboardDisconnectObserver = nil

        controllerNumbers = 0

        for controller in controllers.values {
            cleanupControllerHaptics(controller)
            cleanupControllerMotion(controller)
            cleanupControllerBattery(controller)
        }
        controllers.removeAll()

        for controller in GCController.controllers() {
            if Self.isSupportedGamepad(controller) {
                unregisterControllerCallbacks(controller)
            }
        }

        for mouse in GCMouse.mice() {
            unregisterMouseCallbacks(mouse)
        }
    }

    @objc func getOscController() -> Controller {
        oscController
    }

    @objc func getConnectedGamepadCount() -> Int {
        controllers.count
    }

    @objc func initAutoOnScreenControlMode(_ osc: OnScreenControls) {
        self.osc = osc
        updateAutoOnScreenControlMode()
    }

    @objc static func getConnectedGamepadMask(_ streamConfig: StreamConfiguration) -> Int32 {
        var mask: Int32 = 0

        if streamConfig.multiController {
            var i: Int32 = 0
            for controller in GCController.controllers() {
                if isSupportedGamepad(controller) {
                    mask |= 1 << i
                    i += 1
                }
            }
        } else {
            mask = 0x1
        }

        let level = OnScreenControlsLevel(rawValue: Int(streamConfig.onscreenControls)) ?? .off
        if level != .off && (!hasKeyboardOrMouse() || level != .auto) && !streamConfig.absoluteTouchMode {
            mask |= 0x1
        }

        return mask
    }

    // MARK: - Button/stick/trigger updates (called from OnScreenControls & StreamView)

    @objc func updateLeftStick(_ controller: Controller, x: Int16, y: Int16) {
        objc_sync_enter(controller)
        controller.lastLeftStickX = x
        controller.lastLeftStickY = y
        objc_sync_exit(controller)
    }

    @objc func updateRightStick(_ controller: Controller, x: Int16, y: Int16) {
        objc_sync_enter(controller)
        controller.lastRightStickX = x
        controller.lastRightStickY = y
        objc_sync_exit(controller)
    }

    @objc func updateLeftTrigger(_ controller: Controller, left: UInt8) {
        objc_sync_enter(controller)
        controller.lastLeftTrigger = left
        objc_sync_exit(controller)
    }

    @objc func updateRightTrigger(_ controller: Controller, right: UInt8) {
        objc_sync_enter(controller)
        controller.lastRightTrigger = right
        objc_sync_exit(controller)
    }

    @objc func updateTriggers(_ controller: Controller, left: UInt8, right: UInt8) {
        objc_sync_enter(controller)
        controller.lastLeftTrigger = left
        controller.lastRightTrigger = right
        objc_sync_exit(controller)
    }

    @objc func updateButtonFlags(_ controller: Controller, flags: Int32) {
        objc_sync_enter(controller)
        let releasedButtons = (controller.lastButtonFlags ^ flags) & ~flags
        let pressedButtons = (controller.lastButtonFlags ^ flags) & flags
        controller.lastButtonFlags = flags
        handleSpecialCombosReleased(controller, releasedButtons: releasedButtons)
        handleSpecialCombosPressed(controller, pressedButtons: pressedButtons)
        objc_sync_exit(controller)
    }

    @objc func setButtonFlag(_ controller: Controller, flags: Int32) {
        objc_sync_enter(controller)
        controller.lastButtonFlags |= flags
        handleSpecialCombosPressed(controller, pressedButtons: flags)
        objc_sync_exit(controller)
    }

    @objc func clearButtonFlag(_ controller: Controller, flags: Int32) {
        objc_sync_enter(controller)
        controller.lastButtonFlags &= ~flags
        handleSpecialCombosReleased(controller, releasedButtons: flags)
        objc_sync_exit(controller)
    }

    @objc func updateFinished(_ controller: Controller) {
        var exitRequested = false

        controllerStreamLock.lock()
        objc_sync_enter(controller)

        // Handle Start+Select+L1+R1 gamepad quit combo
        if controller.lastButtonFlags == (PLAY_FLAG | BACK_FLAG | LB_FLAG | RB_FLAG) {
            controller.lastButtonFlags = 0
            exitRequested = true
        }

        if reportControllerArrival(controller) {
            var buttonFlags = UInt32(bitPattern: controller.lastButtonFlags)
            var leftTrigger = controller.lastLeftTrigger
            var rightTrigger = controller.lastRightTrigger
            var leftStickX = controller.lastLeftStickX
            var leftStickY = controller.lastLeftStickY
            var rightStickX = controller.lastRightStickX
            var rightStickY = controller.lastRightStickY

            if let merged = controller.mergedWithController {
                buttonFlags |= UInt32(bitPattern: merged.lastButtonFlags)
                leftTrigger = max(leftTrigger, merged.lastLeftTrigger)
                rightTrigger = max(rightTrigger, merged.lastRightTrigger)
                leftStickX = abs(leftStickX) > abs(merged.lastLeftStickX) ? leftStickX : merged.lastLeftStickX
                leftStickY = abs(leftStickY) > abs(merged.lastLeftStickY) ? leftStickY : merged.lastLeftStickY
                rightStickX = abs(rightStickX) > abs(merged.lastRightStickX) ? rightStickX : merged.lastRightStickX
                rightStickY = abs(rightStickY) > abs(merged.lastRightStickY) ? rightStickY : merged.lastRightStickY
            }

            let playerIdx: Int16 = multiController ? Int16(controller.playerIndex) : 0
            LiSendMultiControllerEvent(playerIdx, Int16(getActiveGamepadMask()),
                                       Int32(bitPattern: buttonFlags), leftTrigger, rightTrigger,
                                       leftStickX, leftStickY, rightStickX, rightStickY)
        }

        objc_sync_exit(controller)
        controllerStreamLock.unlock()

        if exitRequested {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.streamExitRequested()
            }
        }
    }

    // MARK: - Rumble / Motion / LED

    @objc func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        let controller = controllers[Int(controllerNumber)]
        if controller == nil && controllerNumber == 0 && oscEnabled {
            // TODO: Rumble emulation for OSC
        }
        guard let controller else { return }

        controller.lowFreqMotor?.setMotorAmplitude(lowFreqMotor)
        controller.highFreqMotor?.setMotorAmplitude(highFreqMotor)
    }

    @objc func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {
        let controller = controllers[Int(controllerNumber)]
        if controller == nil && controllerNumber == 0 && oscEnabled {
            // TODO: Trigger rumble emulation for OSC
        }
        guard let controller else { return }

        controller.leftTriggerMotor?.setMotorAmplitude(leftTrigger)
        controller.rightTriggerMotor?.setMotorAmplitude(rightTrigger)
    }

    @objc func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {
        guard let controller = controllers[Int(controllerNumber)],
              let motion = controller.gamepad?.motion else { return }

        switch motionType {
        case UInt8(LI_MOTION_TYPE_ACCEL):
            controller.accelTimer?.invalidate()
            controller.accelTimer = nil

            if reportRateHz > 0 && motion.hasGravityAndUserAcceleration {
                controller.lastAccelSample = GCAcceleration()
                nonisolated(unsafe) let motion = motion

                DispatchQueue.main.sync {
                    controller.accelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(reportRateHz), repeats: true) { _ in
                        let last = controller.lastAccelSample
                        let sample = motion.acceleration
                        if sample.x == last.x && sample.y == last.y && sample.z == last.z { return }
                        controller.lastAccelSample = sample

                        LiSendControllerMotionEvent(UInt8(controllerNumber),
                                                    UInt8(LI_MOTION_TYPE_ACCEL),
                                                    Float(sample.x) * -9.80665,
                                                    Float(sample.y) * -9.80665,
                                                    Float(sample.z) * -9.80665)
                    }
                }
            }

        case UInt8(LI_MOTION_TYPE_GYRO):
            controller.gyroTimer?.invalidate()
            controller.gyroTimer = nil

            if reportRateHz > 0 && motion.hasRotationRate {
                controller.lastGyroSample = GCRotationRate()
                nonisolated(unsafe) let motion = motion

                DispatchQueue.main.sync {
                    controller.gyroTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(reportRateHz), repeats: true) { _ in
                        let last = controller.lastGyroSample
                        let sample = motion.rotationRate
                        if sample.x == last.x && sample.y == last.y && sample.z == last.z { return }
                        controller.lastGyroSample = sample

                        LiSendControllerMotionEvent(UInt8(controllerNumber),
                                                    UInt8(LI_MOTION_TYPE_GYRO),
                                                    Float(sample.x) * 57.2957795,
                                                    Float(sample.z) * 57.2957795,
                                                    Float(sample.y) * -57.2957795)
                    }
                }
            }

        default:
            break
        }

        if motion.sensorsRequireManualActivation {
            motion.sensorsActive = controller.gyroTimer != nil || controller.accelTimer != nil
        }
    }

    @objc func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {
        guard let controller = controllers[Int(controllerNumber)],
              let light = controller.gamepad?.light else { return }

        light.color = GCColor(red: Float(r) / 255.0, green: Float(g) / 255.0, blue: Float(b) / 255.0)
    }

    // MARK: - Static helpers

    @objc static func hasKeyboardOrMouse() -> Bool {
        GCMouse.mice().count > 0 || GCKeyboard.coalesced != nil
    }

    // MARK: - Private

    private static func isSupportedGamepad(_ controller: GCController) -> Bool {
        controller.extendedGamepad != nil
    }

    private static func getGamepadCount() -> Int {
        GCController.controllers().filter { isSupportedGamepad($0) }.count
    }

    private func getActiveGamepadMask() -> UInt16 {
        (multiController ? UInt16(controllerNumbers) : 1) | (oscEnabled ? 1 : 0)
    }

    // MARK: - Special combos

    private func handleSpecialCombosReleased(_ controller: Controller, releasedButtons: Int32) {
        if (controller.emulatingButtonFlags & EMULATING_SELECT) != 0 && (releasedButtons & (LB_FLAG | PLAY_FLAG)) != 0 {
            controller.lastButtonFlags &= ~BACK_FLAG
            controller.emulatingButtonFlags &= ~EMULATING_SELECT
        }

        if (controller.emulatingButtonFlags & EMULATING_SPECIAL) != 0 {
            if (controller.supportedEmulationFlags & EMULATING_SELECT) != 0 {
                if (releasedButtons & (RB_FLAG | PLAY_FLAG)) != 0 {
                    controller.lastButtonFlags &= ~SPECIAL_FLAG
                    controller.emulatingButtonFlags &= ~EMULATING_SPECIAL
                }
            } else {
                if (releasedButtons & (BACK_FLAG | PLAY_FLAG)) != 0 {
                    controller.lastButtonFlags &= ~SPECIAL_FLAG
                    controller.emulatingButtonFlags &= ~EMULATING_SPECIAL
                }
            }
        }
    }

    private func handleSpecialCombosPressed(_ controller: Controller, pressedButtons: Int32) {
        guard (controller.lastButtonFlags & PLAY_FLAG) != 0 else { return }

        if (controller.lastButtonFlags & LB_FLAG) != 0 {
            if (controller.supportedEmulationFlags & EMULATING_SELECT) != 0 {
                controller.lastButtonFlags |= BACK_FLAG
                controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | LB_FLAG))
                controller.emulatingButtonFlags |= EMULATING_SELECT
            }
        } else if (controller.supportedEmulationFlags & EMULATING_SPECIAL) != 0 {
            if (controller.supportedEmulationFlags & EMULATING_SELECT) != 0 {
                if (controller.lastButtonFlags & RB_FLAG) != 0 {
                    controller.lastButtonFlags |= SPECIAL_FLAG
                    controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | RB_FLAG))
                    controller.emulatingButtonFlags |= EMULATING_SPECIAL
                }
            } else {
                if (controller.lastButtonFlags & BACK_FLAG) != 0 {
                    controller.lastButtonFlags |= SPECIAL_FLAG
                    controller.lastButtonFlags &= ~(pressedButtons & (PLAY_FLAG | BACK_FLAG))
                    controller.emulatingButtonFlags |= EMULATING_SPECIAL
                }
            }
        }
    }

    // MARK: - Controller assignment

    @discardableResult
    private func assignController(_ gcController: GCController) -> Controller? {
        for i: UInt8 in 0..<4 {
            guard (controllerNumbers & (1 << i)) == 0 else { continue }

            controllerNumbers |= (1 << i)
            gcController.playerIndex = GCControllerPlayerIndex(rawValue: Int(i))!

            let limeController = Controller()
            limeController.playerIndex = Int32(i)
            limeController.supportedEmulationFlags = EMULATING_SPECIAL | EMULATING_SELECT
            limeController.gamepad = gcController

            // Player 0 shares state with OSC
            limeController.mergedWithController = oscController
            oscController.mergedWithController = limeController

            if gcController.extendedGamepad?.buttonOptions != nil {
                limeController.supportedEmulationFlags &= ~EMULATING_SELECT
            }
            if gcController.extendedGamepad?.buttonHome != nil {
                limeController.supportedEmulationFlags &= ~EMULATING_SPECIAL
            }

            initializeControllerHaptics(limeController)
            controllers[Int(i)] = limeController

            Self.logger.info("Assigning controller index: \(i)")
            return limeController
        }

        return nil
    }

    // MARK: - Controller arrival reporting

    @discardableResult
    private func reportControllerArrival(_ limeController: Controller) -> Bool {
        guard !limeController.reportedArrival else { return true }

        var type = UInt8(LI_CTYPE_UNKNOWN)
        var capabilities: UInt16 = 0
        var supportedButtonFlags: UInt32 = 0

        if let gc = limeController.gamepad {
            supportedButtonFlags |= UInt32(PLAY_FLAG)

            if gc.extendedGamepad?.dpad != nil {
                supportedButtonFlags |= UInt32(UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG)
            }
            if gc.extendedGamepad?.leftShoulder != nil { supportedButtonFlags |= UInt32(LB_FLAG) }
            if gc.extendedGamepad?.rightShoulder != nil { supportedButtonFlags |= UInt32(RB_FLAG) }
            if gc.extendedGamepad?.buttonOptions != nil { supportedButtonFlags |= UInt32(BACK_FLAG) }
            if gc.extendedGamepad?.buttonHome != nil { supportedButtonFlags |= UInt32(SPECIAL_FLAG) }
            if gc.extendedGamepad?.buttonA != nil { supportedButtonFlags |= UInt32(A_FLAG) }
            if gc.extendedGamepad?.buttonB != nil { supportedButtonFlags |= UInt32(B_FLAG) }
            if gc.extendedGamepad?.buttonX != nil { supportedButtonFlags |= UInt32(X_FLAG) }
            if gc.extendedGamepad?.buttonY != nil { supportedButtonFlags |= UInt32(Y_FLAG) }
            if gc.extendedGamepad?.leftThumbstickButton != nil { supportedButtonFlags |= UInt32(LS_CLK_FLAG) }
            if gc.extendedGamepad?.rightThumbstickButton != nil { supportedButtonFlags |= UInt32(RS_CLK_FLAG) }

            // Xbox paddles
            if gc.physicalInputProfile.buttons[GCInputXboxPaddleOne] != nil { supportedButtonFlags |= UInt32(PADDLE1_FLAG) }
            if gc.physicalInputProfile.buttons[GCInputXboxPaddleTwo] != nil { supportedButtonFlags |= UInt32(PADDLE2_FLAG) }
            if gc.physicalInputProfile.buttons[GCInputXboxPaddleThree] != nil { supportedButtonFlags |= UInt32(PADDLE3_FLAG) }
            if gc.physicalInputProfile.buttons[GCInputXboxPaddleFour] != nil { supportedButtonFlags |= UInt32(PADDLE4_FLAG) }
            if gc.physicalInputProfile.buttons[GCInputButtonShare] != nil { supportedButtonFlags |= UInt32(MISC_FLAG) }

            // DualShock/DualSense
            if gc.physicalInputProfile.buttons[GCInputDualShockTouchpadButton] != nil { supportedButtonFlags |= UInt32(TOUCHPAD_FLAG) }
            if gc.physicalInputProfile.dpads[GCInputDualShockTouchpadOne] != nil { capabilities |= UInt16(LI_CCAP_TOUCHPAD) }

            if gc.extendedGamepad is GCXboxGamepad { type = UInt8(LI_CTYPE_XBOX) }
            if gc.extendedGamepad is GCDualShockGamepad { type = UInt8(LI_CTYPE_PS) }
            if gc.extendedGamepad is GCDualSenseGamepad { type = UInt8(LI_CTYPE_PS) }

            if let haptics = gc.haptics {
                if haptics.supportedLocalities.contains(.handles) { capabilities |= UInt16(LI_CCAP_RUMBLE) }
                if haptics.supportedLocalities.contains(.triggers) { capabilities |= UInt16(LI_CCAP_TRIGGER_RUMBLE) }
            }

            if let motion = gc.motion {
                if motion.hasGravityAndUserAcceleration { capabilities |= UInt16(LI_CCAP_ACCEL) }
                if motion.hasRotationRate { capabilities |= UInt16(LI_CCAP_GYRO) }
            }

            if gc.light != nil { capabilities |= UInt16(LI_CCAP_RGB_LED) }
            if gc.battery != nil { capabilities |= UInt16(LI_CCAP_BATTERY_STATE) }
        }

        if LiSendControllerArrivalEvent(UInt8(limeController.playerIndex),
                                         getActiveGamepadMask(),
                                         type,
                                         supportedButtonFlags,
                                         capabilities) != 0 {
            return false
        }

        initializeControllerBattery(limeController)
        limeController.reportedArrival = true
        return true
    }

    // MARK: - Haptics / Motion / Battery lifecycle

    private func initializeControllerHaptics(_ controller: Controller) {
        guard let gp = controller.gamepad else { return }
        controller.lowFreqMotor = HapticContext.createForLowFreqMotor(gp)
        controller.highFreqMotor = HapticContext.createForHighFreqMotor(gp)
        controller.leftTriggerMotor = HapticContext.createForLeftTrigger(gp)
        controller.rightTriggerMotor = HapticContext.createForRightTrigger(gp)
    }

    private func cleanupControllerHaptics(_ controller: Controller) {
        controller.lowFreqMotor?.cleanup()
        controller.highFreqMotor?.cleanup()
        controller.leftTriggerMotor?.cleanup()
        controller.rightTriggerMotor?.cleanup()
    }

    private func cleanupControllerMotion(_ controller: Controller) {
        controller.gyroTimer?.invalidate()
        controller.accelTimer?.invalidate()
        if let motion = controller.gamepad?.motion, motion.sensorsRequireManualActivation {
            motion.sensorsActive = false
        }
    }

    private func initializeControllerBattery(_ controller: Controller) {
        guard let battery = controller.gamepad?.battery else { return }

        controller.batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak controller] _ in
            guard let controller, let battery = controller.gamepad?.battery else { return }

            guard controller.lastBatteryState != battery.batteryState ||
                  controller.lastBatteryLevel != battery.batteryLevel else { return }

            let batteryState: UInt8
            switch battery.batteryState {
            case .full: batteryState = UInt8(LI_BATTERY_STATE_FULL)
            case .charging: batteryState = UInt8(LI_BATTERY_STATE_CHARGING)
            case .discharging: batteryState = UInt8(LI_BATTERY_STATE_DISCHARGING)
            default: batteryState = UInt8(LI_BATTERY_STATE_UNKNOWN)
            }

            LiSendControllerBatteryEvent(UInt8(controller.playerIndex),
                                          batteryState,
                                          UInt8(battery.batteryLevel * 100))

            controller.lastBatteryState = battery.batteryState
            controller.lastBatteryLevel = battery.batteryLevel
        }

        // Fire immediately
        controller.batteryTimer?.fire()
    }

    private func cleanupControllerBattery(_ controller: Controller) {
        controller.batteryTimer?.invalidate()
    }

    // MARK: - Touchpad handling

    private func handleControllerTouchpad(_ controller: Controller, touch: GCControllerDirectionPad, index: Int32) {
        let context = index == 0 ? controller.primaryTouch : controller.secondaryTouch

        let normalizedX = (1.0 + touch.xAxis.value) * 0.5
        let normalizedY = 1.0 - (1.0 + touch.yAxis.value) * 0.5

        if (context.lastX != 0 || context.lastY != 0) && (touch.xAxis.value == 0 && touch.yAxis.value == 0) {
            LiSendControllerTouchEvent(UInt8(controller.playerIndex), UInt8(LI_TOUCH_EVENT_UP), UInt32(index), normalizedX, normalizedY, 1.0)
        } else if touch.xAxis.value != 0 || touch.yAxis.value != 0 {
            if context.lastX == 0 && context.lastY == 0 {
                LiSendControllerTouchEvent(UInt8(controller.playerIndex), UInt8(LI_TOUCH_EVENT_DOWN), UInt32(index), normalizedX, normalizedY, 1.0)
            } else if context.lastX != touch.xAxis.value || context.lastY != touch.yAxis.value {
                LiSendControllerTouchEvent(UInt8(controller.playerIndex), UInt8(LI_TOUCH_EVENT_MOVE), UInt32(index), normalizedX, normalizedY, 1.0)
            }
        }

        if index == 0 {
            controller.primaryTouch = Controller.TouchContext(lastX: touch.xAxis.value, lastY: touch.yAxis.value)
        } else {
            controller.secondaryTouch = Controller.TouchContext(lastX: touch.xAxis.value, lastY: touch.yAxis.value)
        }
    }

    // MARK: - Gamepad callback registration

    private func registerControllerCallbacks(_ controller: GCController) {
        guard controller.extendedGamepad != nil else {
            Self.logger.warning("Tried to register controller callbacks on unsupported controller")
            return
        }

        // Legacy paused handler for older MFi controllers without Select button
        let useLegacyPausedHandler = controller.extendedGamepad?.buttonOptions == nil

        if useLegacyPausedHandler {
            controller.controllerPausedHandler = { [weak self] gc in
                guard let self, let limeController = self.controllers[Int(gc.playerIndex.rawValue)] else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    self.setButtonFlag(limeController, flags: PLAY_FLAG)
                    self.updateFinished(limeController)
                    usleep(100 * 1000)
                    self.clearButtonFlag(limeController, flags: PLAY_FLAG)
                    self.updateFinished(limeController)
                }
            }
        }

        // Disable system gestures on all gamepad elements
        for element in controller.physicalInputProfile.allElements {
            element.preferredSystemGestureState = .disabled
        }

        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self, let limeController = self.controllers[Int(gamepad.controller!.playerIndex.rawValue)] else { return }

            if self.swapABXYButtons {
                self.updateButton(limeController, flag: B_FLAG, pressed: gamepad.buttonA.isPressed)
                self.updateButton(limeController, flag: A_FLAG, pressed: gamepad.buttonB.isPressed)
                self.updateButton(limeController, flag: Y_FLAG, pressed: gamepad.buttonX.isPressed)
                self.updateButton(limeController, flag: X_FLAG, pressed: gamepad.buttonY.isPressed)
            } else {
                self.updateButton(limeController, flag: A_FLAG, pressed: gamepad.buttonA.isPressed)
                self.updateButton(limeController, flag: B_FLAG, pressed: gamepad.buttonB.isPressed)
                self.updateButton(limeController, flag: X_FLAG, pressed: gamepad.buttonX.isPressed)
                self.updateButton(limeController, flag: Y_FLAG, pressed: gamepad.buttonY.isPressed)
            }

            self.updateButton(limeController, flag: UP_FLAG, pressed: gamepad.dpad.up.isPressed)
            self.updateButton(limeController, flag: DOWN_FLAG, pressed: gamepad.dpad.down.isPressed)
            self.updateButton(limeController, flag: LEFT_FLAG, pressed: gamepad.dpad.left.isPressed)
            self.updateButton(limeController, flag: RIGHT_FLAG, pressed: gamepad.dpad.right.isPressed)

            self.updateButton(limeController, flag: LB_FLAG, pressed: gamepad.leftShoulder.isPressed)
            self.updateButton(limeController, flag: RB_FLAG, pressed: gamepad.rightShoulder.isPressed)

            if gamepad.leftThumbstickButton != nil {
                self.updateButton(limeController, flag: LS_CLK_FLAG, pressed: gamepad.leftThumbstickButton!.isPressed)
            }
            if gamepad.rightThumbstickButton != nil {
                self.updateButton(limeController, flag: RS_CLK_FLAG, pressed: gamepad.rightThumbstickButton!.isPressed)
            }

            if gamepad.buttonOptions != nil {
                self.updateButton(limeController, flag: BACK_FLAG, pressed: gamepad.buttonOptions!.isPressed)
                self.updateButton(limeController, flag: PLAY_FLAG, pressed: gamepad.buttonMenu.isPressed)
            }

            if gamepad.buttonHome != nil {
                self.updateButton(limeController, flag: SPECIAL_FLAG, pressed: gamepad.buttonHome!.isPressed)
            }

            // Xbox paddles
            let profile = gamepad.controller!.physicalInputProfile
            if let p1 = profile.buttons[GCInputXboxPaddleOne] {
                self.updateButton(limeController, flag: PADDLE1_FLAG, pressed: p1.isPressed)
            }
            if let p2 = profile.buttons[GCInputXboxPaddleTwo] {
                self.updateButton(limeController, flag: PADDLE2_FLAG, pressed: p2.isPressed)
            }
            if let p3 = profile.buttons[GCInputXboxPaddleThree] {
                self.updateButton(limeController, flag: PADDLE3_FLAG, pressed: p3.isPressed)
            }
            if let p4 = profile.buttons[GCInputXboxPaddleFour] {
                self.updateButton(limeController, flag: PADDLE4_FLAG, pressed: p4.isPressed)
            }
            if let share = profile.buttons[GCInputButtonShare] {
                self.updateButton(limeController, flag: MISC_FLAG, pressed: share.isPressed)
            }

            // DualShock/DualSense touchpad
            if let tp = profile.buttons[GCInputDualShockTouchpadButton] {
                self.updateButton(limeController, flag: TOUCHPAD_FLAG, pressed: tp.isPressed)
            }
            if let tp1 = profile.dpads[GCInputDualShockTouchpadOne] {
                self.handleControllerTouchpad(limeController, touch: tp1, index: 0)
            }
            if let tp2 = profile.dpads[GCInputDualShockTouchpadTwo] {
                self.handleControllerTouchpad(limeController, touch: tp2, index: 1)
            }

            let leftStickX = Int16(gamepad.leftThumbstick.xAxis.value * 0x7FFE)
            let leftStickY = Int16(gamepad.leftThumbstick.yAxis.value * 0x7FFE)
            let rightStickX = Int16(gamepad.rightThumbstick.xAxis.value * 0x7FFE)
            let rightStickY = Int16(gamepad.rightThumbstick.yAxis.value * 0x7FFE)
            let leftTrigger = UInt8(gamepad.leftTrigger.value * 0xFF)
            let rightTrigger = UInt8(gamepad.rightTrigger.value * 0xFF)

            self.updateLeftStick(limeController, x: leftStickX, y: leftStickY)
            self.updateRightStick(limeController, x: rightStickX, y: rightStickY)
            self.updateTriggers(limeController, left: leftTrigger, right: rightTrigger)
            self.updateFinished(limeController)
        }
    }

    private func unregisterControllerCallbacks(_ controller: GCController) {
        controller.controllerPausedHandler = nil

        if controller.extendedGamepad != nil {
            for element in controller.physicalInputProfile.allElements {
                element.preferredSystemGestureState = .enabled
            }
            controller.extendedGamepad?.valueChangedHandler = nil
        }
    }

    private func updateButton(_ controller: Controller, flag: Int32, pressed: Bool) {
        if pressed {
            setButtonFlag(controller, flags: flag)
        } else {
            clearButtonFlag(controller, flags: flag)
        }
    }

    // MARK: - Mouse callback registration

    private func registerMouseCallbacks(_ mouse: GCMouse) {
        mouse.mouseInput?.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            guard let self else { return }
            self.accumulatedDeltaX += deltaX / MOUSE_SPEED_DIVISOR
            self.accumulatedDeltaY += -deltaY / MOUSE_SPEED_DIVISOR

            let truncatedX = Int16(self.accumulatedDeltaX)
            let truncatedY = Int16(self.accumulatedDeltaY)

            if truncatedX != 0 || truncatedY != 0 {
                LiSendMouseMoveEvent(truncatedX, truncatedY)
                self.accumulatedDeltaX -= Float(truncatedX)
                self.accumulatedDeltaY -= Float(truncatedY)
            }
        }

        mouse.mouseInput?.leftButton.pressedChangedHandler = { _, _, pressed in
            LiSendMouseButtonEvent(pressed ? CChar(BUTTON_ACTION_PRESS) : CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        }
        mouse.mouseInput?.middleButton?.pressedChangedHandler = { _, _, pressed in
            LiSendMouseButtonEvent(pressed ? CChar(BUTTON_ACTION_PRESS) : CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_MIDDLE))
        }
        mouse.mouseInput?.rightButton?.pressedChangedHandler = { _, _, pressed in
            LiSendMouseButtonEvent(pressed ? CChar(BUTTON_ACTION_PRESS) : CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_RIGHT))
        }

        if let aux = mouse.mouseInput?.auxiliaryButtons {
            if aux.count >= 1 {
                aux[0].pressedChangedHandler = { _, _, pressed in
                    LiSendMouseButtonEvent(pressed ? CChar(BUTTON_ACTION_PRESS) : CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_X1))
                }
            }
            if aux.count >= 2 {
                aux[1].pressedChangedHandler = { _, _, pressed in
                    LiSendMouseButtonEvent(pressed ? CChar(BUTTON_ACTION_PRESS) : CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_X2))
                }
            }
        }

        #if os(tvOS)
        mouse.mouseInput?.scroll.xAxis.valueChangedHandler = { [weak self] _, value in
            guard let self else { return }
            self.accumulatedScrollX += value
            let truncated = Int16(self.accumulatedScrollX)
            if truncated != 0 {
                LiSendHighResHScrollEvent(-Int16(truncated) * 20)
                self.accumulatedScrollX -= Float(truncated)
            }
        }
        mouse.mouseInput?.scroll.yAxis.valueChangedHandler = { [weak self] _, value in
            guard let self else { return }
            self.accumulatedScrollY += value
            let truncated = Int16(self.accumulatedScrollY)
            if truncated != 0 {
                LiSendHighResScrollEvent(Int16(truncated) * 20)
                self.accumulatedScrollY -= Float(truncated)
            }
        }
        #endif
    }

    private func unregisterMouseCallbacks(_ mouse: GCMouse) {
        mouse.mouseInput?.mouseMovedHandler = nil
        mouse.mouseInput?.leftButton.pressedChangedHandler = nil
        mouse.mouseInput?.middleButton?.pressedChangedHandler = nil
        mouse.mouseInput?.rightButton?.pressedChangedHandler = nil

        if let aux = mouse.mouseInput?.auxiliaryButtons {
            for button in aux {
                button.pressedChangedHandler = nil
            }
        }

        #if os(tvOS)
        mouse.mouseInput?.scroll.xAxis.valueChangedHandler = nil
        mouse.mouseInput?.scroll.yAxis.valueChangedHandler = nil
        #endif
    }

    // MARK: - Auto on-screen controls

    private func updateAutoOnScreenControlMode() {
        guard let osc else { return }

        var level: OnScreenControlsLevel = .full

        for controller in GCController.controllers() {
            if controller.extendedGamepad != nil {
                level = .autoGCExtendedGamepad
                if controller.extendedGamepad?.leftThumbstickButton != nil &&
                   controller.extendedGamepad?.rightThumbstickButton != nil {
                    level = .autoGCExtendedGamepadWithStickButtons
                    if controller.extendedGamepad?.buttonOptions != nil {
                        level = .off
                    }
                }
                break
            }
        }

        if level == .full && Self.hasKeyboardOrMouse() {
            level = .off
            LiSendMultiControllerEvent(0, 0, 0, 0, 0, 0, 0, 0, 0)
        }

        osc.setLevel(level)
    }
}
