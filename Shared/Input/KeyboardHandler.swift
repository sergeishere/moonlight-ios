import UIKit

struct KeyEvent {
    var keycode: UInt16 = 0
    var modifierKeycode: UInt16 = 0
    var modifier: UInt8 = 0
}

final class KeyboardSupport {
    static func sendKeyEvent(forPress press: UIPress, down: Bool) -> Bool {
        if let key = press.key {
            return sendKeyEvent(key, down: down)
        }

        let keyCode: Int16
        switch press.type {
        case .upArrow: keyCode = 0x26
        case .downArrow: keyCode = 0x28
        case .leftArrow: keyCode = 0x25
        case .rightArrow: keyCode = 0x27
        default: return false
        }

        LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | keyCode,
                            down ? Int8(KEY_ACTION_DOWN) : Int8(KEY_ACTION_UP), 0)
        return true
    }

    static func sendKeyEvent(_ key: UIKey, down: Bool) -> Bool {
        var modifierFlags: Int8 = 0
        var keyCode: Int16 = 0

        if key.modifierFlags.contains(.shift) { modifierFlags |= Int8(MODIFIER_SHIFT) }
        if key.modifierFlags.contains(.alternate) { modifierFlags |= Int8(MODIFIER_ALT) }
        if key.modifierFlags.contains(.control) { modifierFlags |= Int8(MODIFIER_CTRL) }
        if key.modifierFlags.contains(.command) { modifierFlags |= Int8(MODIFIER_META) }

        let hid = key.keyCode.rawValue

        // A-Z
        if hid >= UIKeyboardHIDUsage.keyboardA.rawValue && hid <= UIKeyboardHIDUsage.keyboardZ.rawValue {
            keyCode = Int16(hid - UIKeyboardHIDUsage.keyboardA.rawValue) + 0x41
        }
        // 0 key (end of HID range, start of VK range)
        else if hid == UIKeyboardHIDUsage.keyboard0.rawValue {
            keyCode = 0x30
        }
        // 1-9
        else if hid >= UIKeyboardHIDUsage.keyboard1.rawValue && hid <= UIKeyboardHIDUsage.keyboard9.rawValue {
            keyCode = Int16(hid - UIKeyboardHIDUsage.keyboard1.rawValue) + 0x31
        }
        // Keypad 0
        else if hid == UIKeyboardHIDUsage.keypad0.rawValue {
            keyCode = 0x60
        }
        // Keypad 1-9
        else if hid >= UIKeyboardHIDUsage.keypad1.rawValue && hid <= UIKeyboardHIDUsage.keypad9.rawValue {
            keyCode = Int16(hid - UIKeyboardHIDUsage.keypad1.rawValue) + 0x61
        }
        // F1-F12
        else if hid >= UIKeyboardHIDUsage.keyboardF1.rawValue && hid <= UIKeyboardHIDUsage.keyboardF12.rawValue {
            keyCode = Int16(hid - UIKeyboardHIDUsage.keyboardF1.rawValue) + 0x70
        }
        // F13-F24
        else if hid >= UIKeyboardHIDUsage.keyboardF13.rawValue && hid <= UIKeyboardHIDUsage.keyboardF24.rawValue {
            keyCode = Int16(hid - UIKeyboardHIDUsage.keyboardF13.rawValue) + 0x7C
        }
        else {
            switch key.keyCode {
            case .keyboardReturnOrEnter: keyCode = 0x0D
            case .keyboardEscape: keyCode = 0x1B
            case .keyboardDeleteOrBackspace: keyCode = 0x08
            case .keyboardTab: keyCode = 0x09
            case .keyboardSpacebar: keyCode = 0x20
            case .keyboardHyphen: keyCode = 0xBD
            case .keyboardEqualSign: keyCode = 0xBB
            case .keyboardOpenBracket: keyCode = 0xDB
            case .keyboardCloseBracket: keyCode = 0xDD
            case .keyboardBackslash: keyCode = 0xDC
            case .keyboardSemicolon: keyCode = 0xBA
            case .keyboardQuote: keyCode = 0xDE
            case .keyboardGraveAccentAndTilde: keyCode = 0xC0
            case .keyboardComma: keyCode = 0xBC
            case .keyboardPeriod: keyCode = 0xBE
            case .keyboardSlash: keyCode = 0xBF
            case .keyboardCapsLock: keyCode = 0x14
            case .keyboardPrintScreen: keyCode = 0x2A
            case .keyboardScrollLock: keyCode = 0x91
            case .keyboardPause: keyCode = 0x13
            case .keyboardInsert: keyCode = 0x2D
            case .keyboardHome: keyCode = 0x24
            case .keyboardPageUp: keyCode = 0x21
            case .keyboardDeleteForward: keyCode = 0x2E
            case .keyboardEnd: keyCode = 0x23
            case .keyboardPageDown: keyCode = 0x22
            case .keyboardRightArrow: keyCode = 0x27
            case .keyboardLeftArrow: keyCode = 0x25
            case .keyboardDownArrow: keyCode = 0x28
            case .keyboardUpArrow: keyCode = 0x26
            case .keypadNumLock: keyCode = 0x90
            case .keypadSlash: keyCode = 0x6F
            case .keypadAsterisk: keyCode = 0x6A
            case .keypadHyphen: keyCode = 0x6D
            case .keypadPlus: keyCode = 0x6B
            case .keypadEnter: keyCode = 0x0D
            case .keypadPeriod: keyCode = 0x6E
            case .keyboardNonUSBackslash: keyCode = 0xE2
            case .keypadComma: keyCode = 0x6C
            case .keyboardCancel: keyCode = 0x03
            case .keyboardClear: keyCode = 0x0C
            case .keyboardCrSelOrProps: keyCode = 0xF7
            case .keyboardExSel: keyCode = 0xF8
            case .keyboardLeftGUI: keyCode = 0x5B
            case .keyboardLeftControl: keyCode = 0xA2
            case .keyboardLeftShift: keyCode = 0xA0
            case .keyboardLeftAlt: keyCode = 0xA4
            case .keyboardRightGUI: keyCode = 0x5C
            case .keyboardRightControl: keyCode = 0xA3
            case .keyboardRightShift: keyCode = 0xA1
            case .keyboardRightAlt: keyCode = 0xA5
            default:
                if hid == 669 { // Globe/Language key on Apple keyboards
                    keyCode = 0x1B // Map to Escape
                } else {
                    return false
                }
            }
        }

        LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | keyCode,
                            down ? Int8(KEY_ACTION_DOWN) : Int8(KEY_ACTION_UP),
                            modifierFlags)
        return true
    }

    static func translateKeyEvent(_ inputChar: unichar, modifierFlags: UIKeyModifierFlags) -> KeyEvent {
        var event = KeyEvent()

        switch modifierFlags {
        case .alphaShift, .shift: addShift(&event)
        case .control: addControl(&event)
        case .command: addMeta(&event)
        case .alternate: addAlt(&event)
        default: break
        }

        if inputChar >= 0x30 && inputChar <= 0x39 {
            event.keycode = inputChar
        } else if inputChar >= 0x41 && inputChar <= 0x5A {
            event.keycode = inputChar
            addShift(&event)
        } else if inputChar >= 0x61 && inputChar <= 0x7A {
            event.keycode = inputChar - (0x61 - 0x41)
        }

        guard let scalar = UnicodeScalar(inputChar) else { return event }
        switch Character(scalar) {
        case " ": event.keycode = 0x20
        case "-": event.keycode = 0xBD
        case "/": event.keycode = 0xBF
        case ":": event.keycode = 0xBA; addShift(&event)
        case ";": event.keycode = 0xBA
        case "(": event.keycode = 0x39; addShift(&event)
        case ")": event.keycode = 0x30; addShift(&event)
        case "$": event.keycode = 0x34; addShift(&event)
        case "&": event.keycode = 0x37; addShift(&event)
        case "@": event.keycode = 0x32; addShift(&event)
        case "\"": event.keycode = 0xDE; addShift(&event)
        case "'": event.keycode = 0xDE
        case "!": event.keycode = 0x31; addShift(&event)
        case "?": event.keycode = 0xBF; addShift(&event)
        case ",": event.keycode = 0xBC
        case "<": event.keycode = 0xBC; addShift(&event)
        case ".": event.keycode = 0xBE
        case ">": event.keycode = 0xBE; addShift(&event)
        case "[": event.keycode = 0xDB
        case "]": event.keycode = 0xDD
        case "{": event.keycode = 0xDB; addShift(&event)
        case "}": event.keycode = 0xDD; addShift(&event)
        case "#": event.keycode = 0x33; addShift(&event)
        case "%": event.keycode = 0x35; addShift(&event)
        case "^": event.keycode = 0x36; addShift(&event)
        case "*": event.keycode = 0x38; addShift(&event)
        case "+": event.keycode = 0xBB; addShift(&event)
        case "=": event.keycode = 0xBB
        case "_": event.keycode = 0xBD; addShift(&event)
        case "\\": event.keycode = 0xDC
        case "|": event.keycode = 0xDC; addShift(&event)
        case "~": event.keycode = 0xC0; addShift(&event)
        case "`": event.keycode = 0xC0
        case "\t": event.keycode = 0x09
        default: break
        }

        return event
    }

    private static func addShift(_ event: inout KeyEvent) {
        event.modifier = UInt8(MODIFIER_SHIFT)
        event.modifierKeycode = 0x10
    }

    private static func addControl(_ event: inout KeyEvent) {
        event.modifier = UInt8(MODIFIER_CTRL)
        event.modifierKeycode = 0x11
    }

    private static func addMeta(_ event: inout KeyEvent) {
        event.modifier = UInt8(MODIFIER_META)
        event.modifierKeycode = 0x5B
    }

    private static func addAlt(_ event: inout KeyEvent) {
        event.modifier = UInt8(MODIFIER_ALT)
        event.modifierKeycode = 0x12
    }
}
