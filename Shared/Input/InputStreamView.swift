import UIKit
import os
#if canImport(GameController)
import GameController
#endif

private let logger = Logger(subsystem: "Moonlight", category: "StreamView")

@MainActor
protocol UserInteractionDelegate: AnyObject {
    func userInteractionBegan()
    func userInteractionEnded()
}

// MARK: - Toolbar Button

#if !os(tvOS) && !os(visionOS)
private class ToolbarButton: UIButton {
    var keyCode: Int16 = 0
    var isToggleable = false
    var isKeyOn = false
}
#endif

// MARK: - StreamView

class StreamView: UIView, UITextFieldDelegate {

    private var onScreenControls: OnScreenControls?
    private var keyInputField: KeyboardInputField?
    private var isInputingText = false
    private var keysDown = Set<Int16>()
    private var streamAspectRatio: Float = 0

    // Mouse state (non-tvOS)
    private var lastMouseButtonMask: Int = 0
    private var lastMouseX: Float = 0
    private var lastMouseY: Float = 0
    private var lastScrollTranslation: CGPoint = .zero

    private var touchHandler: UIResponder?
    private weak var interactionDelegate: (any UserInteractionDelegate)?
    private var interactionTimer: Timer?
    private var hasUserInteracted = false

    private let dictCodes: [String: Int16] = [
        "\r": 0x0D,
        "\u{8}": 0x08,
        UIKeyCommand.inputEscape: 0x1B,
        UIKeyCommand.inputDownArrow: 0x28,
        UIKeyCommand.inputUpArrow: 0x26,
        UIKeyCommand.inputLeftArrow: 0x25,
        UIKeyCommand.inputRightArrow: 0x27,
    ]

    // MARK: - Setup

    func setupStreamView(_ controllerSupport: ControllerSupport,
                          interactionDelegate: any UserInteractionDelegate,
                          config streamConfig: StreamConfiguration) {
        self.interactionDelegate = interactionDelegate
        self.streamAspectRatio = Float(streamConfig.width) / Float(streamConfig.height)

        keysDown = []
        let field = KeyboardInputField(frame: .zero)
        field.keyboardType = .default
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        addSubview(field)
        keyInputField = field

        #if os(tvOS)
        touchHandler = RelativeTouchHandler(view: self)
        #else
        if streamConfig.absoluteTouchMode {
            touchHandler = AbsoluteTouchHandler(view: self)
        } else {
            touchHandler = RelativeTouchHandler(view: self)
        }

        let osc = OnScreenControls(view: self, controllerSup: controllerSupport, streamConfig: streamConfig)!
        let level = OnScreenControlsLevel(rawValue: Int(streamConfig.onscreenControls))!
        if streamConfig.absoluteTouchMode {
            logger.info("On-screen controls disabled in absolute touch mode")
            osc.setLevel(.off)
        } else if level == .auto {
            controllerSupport.initAutoOnScreenControlMode(osc)
        } else {
            logger.info("Setting manual on-screen controls level: \(level.rawValue)")
            osc.setLevel(level)
        }
        onScreenControls = osc

        addInteraction(UIPointerInteraction(delegate: self))

        let discreteScroll = UIPanGestureRecognizer(target: self, action: #selector(mouseWheelMovedDiscrete(_:)))
        discreteScroll.maximumNumberOfTouches = 0
        discreteScroll.allowedScrollTypesMask = .discrete
        discreteScroll.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(discreteScroll)

        let continuousScroll = UIPanGestureRecognizer(target: self, action: #selector(mouseWheelMovedContinuous(_:)))
        continuousScroll.maximumNumberOfTouches = 0
        continuousScroll.allowedScrollTypesMask = .continuous
        continuousScroll.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(continuousScroll)

        let stylusHover = UIHoverGestureRecognizer(target: self, action: #selector(sendStylusHoverEvent(_:)))
        stylusHover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(stylusHover)
        #endif

        becomeFirstResponder()
    }

    // MARK: - Interaction Timer

    private func startInteractionTimer() {
        hasUserInteracted = false
        let timerAlreadyRunning = interactionTimer != nil

        interactionTimer?.invalidate()
        interactionTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self,
                                                selector: #selector(interactionTimerExpired(_:)),
                                                userInfo: nil, repeats: false)
        if !timerAlreadyRunning {
            interactionDelegate?.userInteractionBegan()
        }
    }

    @objc private func interactionTimerExpired(_ timer: Timer) {
        if !hasUserInteracted {
            interactionTimer = nil
            interactionDelegate?.userInteractionEnded()
        } else {
            startInteractionTimer()
        }
    }

    // MARK: - On-Screen Controls

    func showOnScreenControls() {
        #if !os(tvOS)
        onScreenControls?.show()
        #endif
    }

    func getCurrentOscState() -> OnScreenControlsLevel {
        onScreenControls?.getLevel() ?? .off
    }

    // MARK: - Video Area Geometry

    private func getVideoAreaSize() -> CGSize {
        let ratio = CGFloat(streamAspectRatio)
        if bounds.width > bounds.height * ratio {
            return CGSize(width: bounds.height * ratio, height: bounds.height)
        } else {
            return CGSize(width: bounds.width, height: bounds.width / ratio)
        }
    }

    private func adjustCoordinatesForVideoArea(_ point: CGPoint) -> CGPoint {
        var x = point.x - bounds.origin.x
        var y = point.y - bounds.origin.y

        if x < bounds.width / 2 { x -= 1 } else { x += 1 }
        if y < bounds.height / 2 { y -= 1 } else { y += 1 }

        let videoSize = getVideoAreaSize()
        let videoOrigin = CGPoint(x: bounds.width / 2 - videoSize.width / 2,
                                  y: bounds.height / 2 - videoSize.height / 2)

        return CGPoint(
            x: min(max(x, videoOrigin.x), videoOrigin.x + videoSize.width) - videoOrigin.x,
            y: min(max(y, videoOrigin.y), videoOrigin.y + videoSize.height) - videoOrigin.y
        )
    }

    // MARK: - Stylus / Pen Events

    #if !os(tvOS)

    private func getRotation(fromAzimuthAngle angle: CGFloat) -> UInt16 {
        var rotationAngle = Int32((angle - .pi / 2) * (180.0 / .pi))
        if rotationAngle < 0 { rotationAngle += 360 }
        return UInt16(rotationAngle)
    }

    private func getTilt(fromAltitudeAngle angle: CGFloat) -> UInt8 {
        let altitudeDegs = UInt8(abs(Int16(angle * (180.0 / .pi))))
        return 90 - min(90, altitudeDegs)
    }

    private func sendStylusEvent(_ touch: UITouch) -> Bool {
        guard LiGetHostFeatureFlags() & UInt32(LI_FF_PEN_TOUCH_EVENTS) != 0 else { return false }

        let type: UInt8
        switch touch.phase {
        case .began: type = UInt8(LI_TOUCH_EVENT_DOWN)
        case .moved: type = UInt8(LI_TOUCH_EVENT_MOVE)
        case .ended: type = UInt8(LI_TOUCH_EVENT_UP)
        case .cancelled: type = UInt8(LI_TOUCH_EVENT_CANCEL)
        default: return true
        }

        let location = adjustCoordinatesForVideoArea(touch.location(in: self))
        let videoSize = getVideoAreaSize()
        let pressure = Float(touch.force / touch.maximumPossibleForce) / sinf(Float(touch.altitudeAngle))

        return LiSendPenEvent(
            type, UInt8(LI_TOOL_TYPE_PEN), 0,
            Float(location.x / videoSize.width), Float(location.y / videoSize.height),
            pressure, 0.0, 0.0,
            getRotation(fromAzimuthAngle: touch.azimuthAngle(in: self)),
            getTilt(fromAltitudeAngle: touch.altitudeAngle)
        ) != LI_ERR_UNSUPPORTED
    }

    @objc private func sendStylusHoverEvent(_ gesture: UIHoverGestureRecognizer) {
        let type: UInt8
        switch gesture.state {
        case .began, .changed: type = UInt8(LI_TOUCH_EVENT_HOVER)
        case .ended: type = UInt8(LI_TOUCH_EVENT_HOVER_LEAVE)
        default: return
        }

        let location = adjustCoordinatesForVideoArea(gesture.location(in: self))
        let videoSize = getVideoAreaSize()

        LiSendPenEvent(
            type, UInt8(LI_TOOL_TYPE_PEN), 0,
            Float(location.x / videoSize.width), Float(location.y / videoSize.height),
            Float(gesture.zOffset), 0.0, 0.0,
            getRotation(fromAzimuthAngle: gesture.azimuthAngle(in: self)),
            getTilt(fromAltitudeAngle: gesture.altitudeAngle)
        )
    }

    #endif

    // MARK: - Mouse Button Handling

    private func handleMouseButtonEvent(_ buttonAction: Int32, touches: Set<UITouch>, event: UIEvent) -> Bool {
        #if !os(tvOS)
        guard let touch = touches.first, touch.type == .indirectPointer else { return false }

        if GCMouse.current != nil { return true }

        let normalizedButtonMask: UIEvent.ButtonMask
        if buttonAction == BUTTON_ACTION_RELEASE {
            normalizedButtonMask = UIEvent.ButtonMask(rawValue: lastMouseButtonMask & ~event.buttonMask.rawValue)
        } else {
            normalizedButtonMask = event.buttonMask
        }

        let changedButtons = lastMouseButtonMask ^ Int(normalizedButtonMask.rawValue)

        for i in BUTTON_LEFT...BUTTON_X2 {
            let buttonFlag: Int
            switch i {
            case BUTTON_RIGHT: buttonFlag = 1 << 2
            case BUTTON_MIDDLE: buttonFlag = 1 << 3
            default: buttonFlag = 1 << Int(i)
            }

            if changedButtons & buttonFlag != 0 {
                LiSendMouseButtonEvent(CChar(buttonAction), i)
            }
        }

        lastMouseButtonMask = Int(normalizedButtonMask.rawValue)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Touch Events

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        if handleMouseButtonEvent(BUTTON_ACTION_PRESS, touches: touches, event: event) { return }

        logger.debug("Touch down")
        startInteractionTimer()

        #if !os(tvOS)
        for touch in touches where touch.type == .pencil {
            if sendStylusEvent(touch) { return }
        }
        #endif

        if onScreenControls?.handleTouchDownEvent(touches) != true {
            touchHandler?.touchesBegan(touches, with: event)

            if (event.allTouches?.count ?? 0) == 3 {
                toggleKeyboard()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if !os(tvOS)
        guard let event else { return }
        for touch in touches where touch.type == .pencil {
            if sendStylusEvent(touch) { return }
        }

        if let touch = touches.first, touch.type == .indirectPointer {
            if GCMouse.current != nil { return }
            updateCursorLocation(touch.location(in: self), isMouse: true)
            return
        }
        #else
        guard let event else { return }
        #endif

        hasUserInteracted = true

        if onScreenControls?.handleTouchMovedEvent(touches) != true {
            touchHandler?.touchesMoved(touches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        if handleMouseButtonEvent(BUTTON_ACTION_RELEASE, touches: touches, event: event) { return }

        logger.debug("Touch up")
        hasUserInteracted = true

        #if !os(tvOS)
        for touch in touches where touch.type == .pencil {
            if sendStylusEvent(touch) { return }
        }
        #endif

        if onScreenControls?.handleTouchUpEvent(touches) != true {
            touchHandler?.touchesEnded(touches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        touchHandler?.touchesCancelled(touches, with: event)
        _ = handleMouseButtonEvent(BUTTON_ACTION_RELEASE, touches: touches, event: event)
        #if !os(tvOS)
        for touch in touches where touch.type == .pencil {
            _ = sendStylusEvent(touch)
        }
        #endif
    }

    // MARK: - Keyboard Press Events

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if KeyboardSupport.sendKeyEvent(forPress: press, down: true) {
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if KeyboardSupport.sendKeyEvent(forPress: press, down: false) {
                handled = true
            }
        }
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    // MARK: - Mouse Cursor (non-tvOS)

    #if !os(tvOS)
    func updateCursorLocation(_ location: CGPoint, isMouse: Bool) {
        let normalized = adjustCoordinatesForVideoArea(location)
        let videoSize = getVideoAreaSize()

        if normalized.x != CGFloat(lastMouseX) || normalized.y != CGFloat(lastMouseY) || !isMouse {
            if lastMouseX != 0 || lastMouseY != 0 || !isMouse {
                LiSendMousePositionEvent(Int16(normalized.x), Int16(normalized.y),
                                         Int16(videoSize.width), Int16(videoSize.height))
            }
            if isMouse {
                lastMouseX = Float(normalized.x)
                lastMouseY = Float(normalized.y)
            }
        }
    }


    // MARK: - Scroll Wheel

    @objc private func mouseWheelMovedContinuous(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: break
        default:
            lastScrollTranslation = .zero
            return
        }

        let current = gesture.translation(in: self)
        let multiplier: Float = 120.0 * 20.0

        let deltaY = Int16(Float(current.y - lastScrollTranslation.y) / Float(bounds.height) * multiplier)
        if deltaY != 0 {
            LiSendHighResScrollEvent(deltaY)
            lastScrollTranslation = current
        }

        let deltaX = Int16(Float(current.x - lastScrollTranslation.x) / Float(bounds.width) * multiplier)
        if deltaX != 0 {
            LiSendHighResHScrollEvent(-deltaX)
            lastScrollTranslation = current
        }
    }

    @objc private func mouseWheelMovedDiscrete(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: break
        default:
            lastScrollTranslation = .zero
            return
        }

        let current = gesture.translation(in: self)

        let deltaY = Int16(current.y - lastScrollTranslation.y)
        if deltaY != 0 {
            LiSendScrollEvent(deltaY > 0 ? 1 : -1)
        }

        let deltaX = Int16(current.x - lastScrollTranslation.x)
        if deltaX != 0 {
            LiSendHScrollEvent(deltaX < 0 ? 1 : -1)
        }

        lastScrollTranslation = current
    }

    #endif

    // MARK: - Keyboard Toolbar & Text Input

    private func toggleKeyboard() {
        guard let keyInputField else { return }

        if isInputingText {
            logger.debug("Closing the keyboard")
            keyInputField.resignFirstResponder()
            isInputingText = false
        } else {
            logger.debug("Opening the keyboard")
            keyInputField.delegate = self
            keyInputField.text = "0"

            #if !os(tvOS) && !os(visionOS)
            keyInputField.inputAccessoryView = createKeyboardToolbar()
            #endif

            keyInputField.becomeFirstResponder()
            keyInputField.addTarget(self, action: #selector(onKeyboardPressed(_:)), for: .editingChanged)
            keyInputField.undoManager?.disableUndoRegistration()
            isInputingText = true
        }
    }

    #if !os(tvOS) && !os(visionOS)
    private func createKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: bounds.width, height: 44))

        let dismiss = createDismissButton()
        let separator = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        separator.width = 0

        let items: [UIBarButtonItem] = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            dismiss,
            separator,
            createToolbarButton(title: "Win", keyCode: 0x5B, toggleable: true),
            createToolbarButton(systemImage: "escape", keyCode: 0x1B, toggleable: false),
            createToolbarButton(systemImage: "arrow.right.to.line", keyCode: 0x09, toggleable: false),
            createToolbarButton(systemImage: "shift", keyCode: 0xA0, toggleable: true),
            createToolbarButton(title: "Ctrl", keyCode: 0xA2, toggleable: true),
            createToolbarButton(title: "Alt", keyCode: 0xA4, toggleable: true),
            createToolbarButton(systemImage: "delete.backward", keyCode: 0x2E, toggleable: false),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        ]
        toolbar.setItems(items, animated: false)
        return toolbar
    }

    private func createDismissButton() -> UIBarButtonItem {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium, scale: .large)
        let button = ToolbarButton(type: .custom)
        button.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 48, height: 36)
        button.tintColor = .white
        button.keyCode = 0
        button.addTarget(self, action: #selector(toolbarButtonClicked(_:)), for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    private func createToolbarButton(title: String? = nil, systemImage: String? = nil,
                                     keyCode: Int16, toggleable: Bool) -> UIBarButtonItem {
        let button = ToolbarButton(type: .custom)
        if let systemImage {
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            button.setImage(UIImage(systemName: systemImage, withConfiguration: config), for: .normal)
        }
        if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.setTitleColor(.white, for: .normal)
        }
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 30)
        button.tintColor = .white
        button.backgroundColor = .black
        button.layer.cornerRadius = 8
        button.keyCode = keyCode
        button.isToggleable = toggleable
        button.addTarget(self, action: #selector(toolbarButtonClicked(_:)), for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }

    @objc private func toolbarButtonClicked(_ sender: UIButton) {
        guard let button = sender as? ToolbarButton else { return }

        if button.isToggleable {
            button.isKeyOn.toggle()
            if button.isKeyOn {
                button.tintColor = .systemBlue
                button.setTitleColor(.systemBlue, for: .normal)
                button.backgroundColor = .darkGray
            } else {
                button.tintColor = .white
                button.setTitleColor(.white, for: .normal)
                button.backgroundColor = .black
            }
        }

        let keyCode = button.keyCode
        if keyCode == 0 {
            keyInputField?.resignFirstResponder()
            isInputingText = false
        } else if button.isToggleable {
            if button.isKeyOn {
                LiSendKeyboardEvent(keyCode, Int8(KEY_ACTION_DOWN), 0)
                keysDown.insert(keyCode)
            } else {
                LiSendKeyboardEvent(keyCode, Int8(KEY_ACTION_UP), 0)
                keysDown.remove(keyCode)
            }
        } else {
            LiSendKeyboardEvent(keyCode, Int8(KEY_ACTION_DOWN), 0)
            usleep(50_000)
            LiSendKeyboardEvent(keyCode, Int8(KEY_ACTION_UP), 0)
        }
    }
    #endif

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        LiSendKeyboardEvent(0x0D, Int8(KEY_ACTION_DOWN), 0)
        usleep(50_000)
        LiSendKeyboardEvent(0x0D, Int8(KEY_ACTION_UP), 0)
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        for keyCode in keysDown {
            LiSendKeyboardEvent(keyCode, Int8(KEY_ACTION_UP), 0)
        }
        keysDown.removeAll()
    }

    @objc private func onKeyboardPressed(_ textField: UITextField) {
        let inputText = textField.text ?? ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if inputText.isEmpty {
                LiSendKeyboardEvent(0x08, Int8(KEY_ACTION_DOWN), 0)
                usleep(50_000)
                LiSendKeyboardEvent(0x08, Int8(KEY_ACTION_UP), 0)
            } else {
                // Character at index 0 is sentinel "0"
                let chars = Array(inputText.utf16)
                guard chars.count > 1 else { return }

                // Check if any character can't be represented as a basic key event
                let hasUnknown = chars[1...].contains { char in
                    KeyboardSupport.translateKeyEvent(char, modifierFlags: []).keycode == 0
                }

                if hasUnknown {
                    // Send entire string as UTF-8 (skip sentinel)
                    let suffix = String(inputText.dropFirst())
                    if let utf8 = suffix.cString(using: .utf8) {
                        LiSendUtf8TextEvent(utf8, UInt32(strlen(utf8)))
                    }
                } else {
                    for char in chars[1...] {
                        let event = KeyboardSupport.translateKeyEvent(char, modifierFlags: [])
                        self?.sendLowLevelEvent(event)
                    }
                }
            }
        }

        textField.text = "0"
        textField.selectedTextRange = textField.textRange(from: textField.endOfDocument,
                                                          to: textField.endOfDocument)
    }

    // MARK: - UIKeyCommand

    @objc private func specialCharPressed(_ cmd: UIKeyCommand) {
        guard let input = cmd.input, let code = dictCodes[input] else { return }
        var event = KeyboardSupport.translateKeyEvent(0x20, modifierFlags: cmd.modifierFlags)
        event.keycode = UInt16(code)
        sendLowLevelEvent(event)
    }

    @objc private func keyPressed(_ cmd: UIKeyCommand) {
        guard let input = cmd.input, let first = input.utf16.first else { return }
        let event = KeyboardSupport.translateKeyEvent(first, modifierFlags: cmd.modifierFlags)
        sendLowLevelEvent(event)
    }

    private func sendLowLevelEvent(_ event: KeyEvent) {
        DispatchQueue.global(qos: .userInitiated).async {
            if event.modifier != 0 {
                LiSendKeyboardEvent(Int16(event.modifierKeycode), Int8(KEY_ACTION_DOWN), Int8(event.modifier))
            }
            LiSendKeyboardEvent2(Int16(event.keycode), Int8(KEY_ACTION_DOWN), Int8(event.modifier),
                                 Int8(SS_KBE_FLAG_NON_NORMALIZED))
            usleep(50_000)
            LiSendKeyboardEvent2(Int16(event.keycode), Int8(KEY_ACTION_UP), Int8(event.modifier),
                                 Int8(SS_KBE_FLAG_NON_NORMALIZED))
            if event.modifier != 0 {
                LiSendKeyboardEvent(Int16(event.modifierKeycode), Int8(KEY_ACTION_UP), Int8(event.modifier))
            }
        }
    }

    // MARK: - First Responder & Key Commands

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let charset = "qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= "
        var commands = [UIKeyCommand]()

        for char in charset {
            let input = String(char)
            commands.append(UIKeyCommand(input: input, modifierFlags: [], action: #selector(keyPressed(_:))))
            commands.append(UIKeyCommand(input: input, modifierFlags: .shift, action: #selector(keyPressed(_:))))
            commands.append(UIKeyCommand(input: input, modifierFlags: .control, action: #selector(keyPressed(_:))))
            commands.append(UIKeyCommand(input: input, modifierFlags: .alternate, action: #selector(keyPressed(_:))))
        }

        for key in dictCodes.keys {
            let modifierSets: [UIKeyModifierFlags] = [
                [], .shift, [.shift, .alternate], [.shift, .control],
                .control, [.control, .alternate], .alternate,
            ]
            for mods in modifierSets {
                commands.append(UIKeyCommand(input: key, modifierFlags: mods, action: #selector(specialCharPressed(_:))))
            }
        }

        return commands
    }

    // MARK: - Gesture Recognizer Filtering

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer.name == nil || !gestureRecognizer.name!.hasPrefix("kbProductivity.")
    }

    #if !os(tvOS)
    override var isMultipleTouchEnabled: Bool {
        get { true }
        set { }
    }
    #endif
}

// MARK: - UIPointerInteractionDelegate

#if !os(tvOS)
extension StreamView: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction,
                            regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        if GCMouse.current != nil { return nil }

        let videoSize = getVideoAreaSize()
        let videoOrigin = CGPoint(x: bounds.width / 2 - videoSize.width / 2,
                                  y: bounds.height / 2 - videoSize.height / 2)

        if lastMouseButtonMask == 0 {
            updateCursorLocation(request.location, isMouse: true)
        }

        return UIPointerRegion(rect: CGRect(origin: videoOrigin, size: videoSize), identifier: nil)
    }

    func pointerInteraction(_ interaction: UIPointerInteraction,
                            styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .hidden()
    }
}
#endif
