//
//  OnScreenControls.swift
//  Moonlight
//
//  Converted from OnScreenControls.h/m (originally by Diego Waxemberg, 12/28/14).
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

import UIKit
import os

// MARK: - OnScreenControlsLevel

@objc(OnScreenControlsLevel)
enum OnScreenControlsLevel: Int {
    case off = 0
    case auto
    case simple
    case full

    // Internal levels selected by ControllerSupport
    case autoGCGamepad
    case autoGCExtendedGamepad
    case autoGCExtendedGamepadWithStickButtons
}

// MARK: - OnScreenControls

@objc(OnScreenControls)
class OnScreenControls: NSObject {

    private static let logger = Logger(subsystem: "Moonlight", category: "OnScreenControls")

    // MARK: - Constants

    private let edgeWidth: CGFloat = 0.05
    private let buttonDist: CGFloat = 20
    private let dPadDist: CGFloat = 10
    private let deadZonePadding: CGFloat = 15
    private let stickClickRate: Double = 100 // milliseconds
    private let stickDeadZone: Float = 0.1

    // MARK: - Layout properties (instance, not static)

    private var buttonCenterX: CGFloat = 0
    private var buttonCenterY: CGFloat = 0

    private var dPadCenterX: CGFloat = 0
    private var dPadCenterY: CGFloat = 0

    private var stickInnerSize: CGFloat = 0
    private var stickOuterSize: CGFloat = 0
    private var lsCenterX: CGFloat = 0
    private var lsCenterY: CGFloat = 0
    private var rsCenterX: CGFloat = 0
    private var rsCenterY: CGFloat = 0

    private var startX: CGFloat = 0
    private var startY: CGFloat = 0
    private var selectX: CGFloat = 0
    private var selectY: CGFloat = 0

    private var r1X: CGFloat = 0
    private var r1Y: CGFloat = 0
    private var r2X: CGFloat = 0
    private var r2Y: CGFloat = 0
    private var r3X: CGFloat = 0
    private var r3Y: CGFloat = 0
    private var l1X: CGFloat = 0
    private var l1Y: CGFloat = 0
    private var l2X: CGFloat = 0
    private var l2Y: CGFloat = 0
    private var l3X: CGFloat = 0
    private var l3Y: CGFloat = 0

    // MARK: - CALayers for on-screen buttons

    private let aButton = CALayer()
    private let bButton = CALayer()
    private let xButton = CALayer()
    private let yButton = CALayer()
    private let upButton = CALayer()
    private let downButton = CALayer()
    private let leftButton = CALayer()
    private let rightButton = CALayer()
    private let leftStickBackground = CALayer()
    private let leftStick = CALayer()
    private let rightStickBackground = CALayer()
    private let rightStick = CALayer()
    private let startButton = CALayer()
    private let selectButton = CALayer()
    private let r1Button = CALayer()
    private let r2Button = CALayer()
    private let r3Button = CALayer()
    private let l1Button = CALayer()
    private let l2Button = CALayer()
    private let l3Button = CALayer()

    // MARK: - Touch tracking

    private var aTouch: UITouch?
    private var bTouch: UITouch?
    private var xTouch: UITouch?
    private var yTouch: UITouch?
    private var dpadTouch: UITouch?
    private var lsTouch: UITouch?
    private var rsTouch: UITouch?
    private var startTouch: UITouch?
    private var selectTouch: UITouch?
    private var r1Touch: UITouch?
    private var r2Touch: UITouch?
    private var r3Touch: UITouch?
    private var l1Touch: UITouch?
    private var l2Touch: UITouch?
    private var l3Touch: UITouch?

    private var l3TouchStart: Date?
    private var r3TouchStart: Date?
    private var l3Set = false
    private var r3Set = false

    // MARK: - State

    private let iPad: Bool
    private let controlArea: CGRect
    private weak var view: UIView?
    private var level: OnScreenControlsLevel = .off
    private var visible = false

    private let controllerSupport: ControllerSupport
    private let controller: Controller
    private var deadTouches = [UITouch]()
    private let swapABXY: Bool

    // MARK: - Init

    @objc init?(view: UIView, controllerSup controllerSupport: ControllerSupport, streamConfig: StreamConfiguration) {
        self.view = view
        self.controllerSupport = controllerSupport
        self.controller = controllerSupport.getOscController()
        self.swapABXY = streamConfig.swapABXYButtons

        self.iPad = (UIDevice.current.userInterfaceIdiom == .pad)

        var area = CGRect(x: 0, y: 0, width: view.frame.size.width, height: view.frame.size.height)
        if iPad {
            // Cut down the control area on an iPad so the controls are more reachable
            area.size.height = view.frame.size.height / 2.0
            area.origin.y = view.frame.size.height - area.size.height
        } else {
            area.origin.x = area.size.width * edgeWidth
            area.size.width -= area.origin.x * 2
        }
        self.controlArea = area

        super.init()
    }

    // MARK: - Public API

    @objc func show() {
        visible = true
        updateControls()
    }

    @objc func setLevel(_ level: OnScreenControlsLevel) {
        self.level = level

        // Only update controls if we're showing, otherwise show will do it for us.
        if visible {
            updateControls()
        }
    }

    @objc func getLevel() -> OnScreenControlsLevel {
        return level
    }

    // MARK: - Update Controls

    private func updateControls() {
        switch level {
        case .off:
            hideButtons()
            hideBumpers()
            hideTriggers()
            hideStartSelect()
            hideSticks()
            hideL3R3()

        case .autoGCGamepad:
            // GCGamepad is missing triggers, both analog sticks, and the select button
            setupGamepadControls()
            hideButtons()
            hideBumpers()
            hideL3R3()
            drawTriggers()
            drawStartSelect()
            drawSticks()

        case .autoGCExtendedGamepad:
            // GCExtendedGamepad is missing R3, L3, and select
            setupExtendedGamepadControls()
            hideButtons()
            hideBumpers()
            hideTriggers()
            drawStartSelect()
            hideSticks()
            drawL3R3()

        case .autoGCExtendedGamepadWithStickButtons:
            // This variant has L3 and R3 but is still missing Select
            setupExtendedGamepadControls()
            hideButtons()
            hideBumpers()
            hideTriggers()
            hideL3R3()
            drawStartSelect()
            hideSticks()

        case .simple:
            setupSimpleControls()
            hideTriggers()
            hideL3R3()
            hideBumpers()
            hideSticks()
            drawStartSelect()
            drawButtons()

        case .full:
            setupComplexControls()
            drawButtons()
            drawStartSelect()
            drawBumpers()
            drawTriggers()
            drawSticks()
            hideL3R3() // Full controls don't need these; they have the sticks

        default:
            Self.logger.warning("Unknown on-screen controls level: \(self.level.rawValue)")
        }
    }

    // MARK: - Layout Setup

    /// For GCExtendedGamepad controls we move start, select, L3, and R3 to the button area.
    private func setupExtendedGamepadControls() {
        setupComplexControls()

        startX = controlArea.size.width * 0.95 + controlArea.origin.x
        startY = controlArea.size.height * 0.9 + controlArea.origin.y
        selectX = controlArea.size.width * 0.05 + controlArea.origin.x
        selectY = controlArea.size.height * 0.9 + controlArea.origin.y

        l3Y = controlArea.size.height * 0.85 + controlArea.origin.y
        r3Y = controlArea.size.height * 0.85 + controlArea.origin.y

        if iPad {
            l3X = controlArea.size.width * 0.15 + controlArea.origin.x
            r3X = controlArea.size.width * 0.85 + controlArea.origin.x
        } else {
            l3X = controlArea.size.width * 0.25 + controlArea.origin.x
            r3X = controlArea.size.width * 0.75 + controlArea.origin.x
        }
    }

    /// For GCGamepad controls we move triggers, start, and select
    /// to sit right above the analog sticks.
    private func setupGamepadControls() {
        setupComplexControls()

        l2Y = controlArea.size.height * 0.75 + controlArea.origin.y
        l2X = controlArea.size.width * 0.05 + controlArea.origin.x

        r2Y = controlArea.size.height * 0.75 + controlArea.origin.y
        r2X = controlArea.size.width * 0.95 + controlArea.origin.x

        startX = controlArea.size.width * 0.95 + controlArea.origin.x
        startY = controlArea.size.height * 0.95 + controlArea.origin.y
        selectX = controlArea.size.width * 0.05 + controlArea.origin.x
        selectY = controlArea.size.height * 0.95 + controlArea.origin.y

        if iPad {
            // The analog sticks are kept closer to the sides on iPad
            lsCenterX = controlArea.size.width * 0.15 + controlArea.origin.x
            rsCenterX = controlArea.size.width * 0.85 + controlArea.origin.x
        }
    }

    /// For simple controls we move the triggers and buttons to the bottom.
    private func setupSimpleControls() {
        setupComplexControls()

        startY = controlArea.size.height * 0.9 + controlArea.origin.y
        selectY = controlArea.size.height * 0.9 + controlArea.origin.y

        l2Y = controlArea.size.height * 0.9 + controlArea.origin.y
        l2X = controlArea.size.width * 0.1 + controlArea.origin.x

        r2Y = controlArea.size.height * 0.9 + controlArea.origin.y
        r2X = controlArea.size.width * 0.9 + controlArea.origin.x

        if iPad {
            // Lower the D-pad and buttons on iPad
            dPadCenterY = controlArea.size.height * 0.75 + controlArea.origin.y
            buttonCenterY = controlArea.size.height * 0.75 + controlArea.origin.y

            // Move Start and Select closer to sides
            selectX = controlArea.size.width * 0.2 + controlArea.origin.x
            startX = controlArea.size.width * 0.8 + controlArea.origin.x
        } else {
            selectX = controlArea.size.width * 0.4 + controlArea.origin.x
            startX = controlArea.size.width * 0.6 + controlArea.origin.x
        }
    }

    private func setupComplexControls() {
        dPadCenterX = controlArea.size.width * 0.1 + controlArea.origin.x
        dPadCenterY = controlArea.size.height * 0.60 + controlArea.origin.y
        buttonCenterX = controlArea.size.width * 0.9 + controlArea.origin.x
        buttonCenterY = controlArea.size.height * 0.60 + controlArea.origin.y

        if iPad {
            // The analog sticks are kept closer to the sides on iPad
            lsCenterX = controlArea.size.width * 0.22 + controlArea.origin.x
            lsCenterY = controlArea.size.height * 0.80 + controlArea.origin.y
            rsCenterX = controlArea.size.width * 0.77 + controlArea.origin.x
            rsCenterY = controlArea.size.height * 0.80 + controlArea.origin.y
        } else {
            lsCenterX = controlArea.size.width * 0.35 + controlArea.origin.x
            lsCenterY = controlArea.size.height * 0.75 + controlArea.origin.y
            rsCenterX = controlArea.size.width * 0.65 + controlArea.origin.x
            rsCenterY = controlArea.size.height * 0.75 + controlArea.origin.y
        }

        startX = controlArea.size.width * 0.9 + controlArea.origin.x
        startY = controlArea.size.height * 0.9 + controlArea.origin.y
        selectX = controlArea.size.width * 0.1 + controlArea.origin.x
        selectY = controlArea.size.height * 0.9 + controlArea.origin.y

        l1Y = controlArea.size.height * 0.27 + controlArea.origin.y
        l2Y = controlArea.size.height * 0.1 + controlArea.origin.y
        r1Y = controlArea.size.height * 0.27 + controlArea.origin.y
        r2Y = controlArea.size.height * 0.1 + controlArea.origin.y

        if iPad {
            // Move L/R buttons closer to the side on iPad
            l1X = controlArea.size.width * 0.05 + controlArea.origin.x
            l2X = controlArea.size.width * 0.05 + controlArea.origin.x
            r1X = controlArea.size.width * 0.95 + controlArea.origin.x
            r2X = controlArea.size.width * 0.95 + controlArea.origin.x
        } else {
            l1X = controlArea.size.width * 0.1 + controlArea.origin.x
            l2X = controlArea.size.width * 0.1 + controlArea.origin.x
            r1X = controlArea.size.width * 0.9 + controlArea.origin.x
            r2X = controlArea.size.width * 0.9 + controlArea.origin.x
        }
    }

    // MARK: - Draw helpers

    private func drawButtons() {
        guard let view else { return }

        let aButtonImage = UIImage(named: "AButton")!
        let bButtonImage = UIImage(named: "BButton")!
        let xButtonImage = UIImage(named: "XButton")!
        let yButtonImage = UIImage(named: "YButton")!

        let aButtonFrame = CGRect(
            x: buttonCenterX - aButtonImage.size.width / 2,
            y: buttonCenterY + buttonDist,
            width: aButtonImage.size.width,
            height: aButtonImage.size.height
        )
        let bButtonFrame = CGRect(
            x: buttonCenterX + buttonDist,
            y: buttonCenterY - bButtonImage.size.height / 2,
            width: bButtonImage.size.width,
            height: bButtonImage.size.height
        )
        let xButtonFrame = CGRect(
            x: buttonCenterX - buttonDist - xButtonImage.size.width,
            y: buttonCenterY - xButtonImage.size.height / 2,
            width: xButtonImage.size.width,
            height: xButtonImage.size.height
        )
        let yButtonFrame = CGRect(
            x: buttonCenterX - yButtonImage.size.width / 2,
            y: buttonCenterY - buttonDist - yButtonImage.size.height,
            width: yButtonImage.size.width,
            height: yButtonImage.size.height
        )

        // A button
        aButton.contents = aButtonImage.cgImage
        aButton.frame = swapABXY ? bButtonFrame : aButtonFrame
        view.layer.addSublayer(aButton)

        // B button
        bButton.contents = bButtonImage.cgImage
        bButton.frame = swapABXY ? aButtonFrame : bButtonFrame
        view.layer.addSublayer(bButton)

        // X button
        xButton.contents = xButtonImage.cgImage
        xButton.frame = swapABXY ? yButtonFrame : xButtonFrame
        view.layer.addSublayer(xButton)

        // Y button
        yButton.contents = yButtonImage.cgImage
        yButton.frame = swapABXY ? xButtonFrame : yButtonFrame
        view.layer.addSublayer(yButton)

        // Down button
        let downButtonImage = UIImage(named: "DownButton")!
        downButton.frame = CGRect(
            x: dPadCenterX - downButtonImage.size.width / 2,
            y: dPadCenterY + dPadDist,
            width: downButtonImage.size.width,
            height: downButtonImage.size.height
        )
        downButton.contents = downButtonImage.cgImage
        view.layer.addSublayer(downButton)

        // Right button
        let rightButtonImage = UIImage(named: "RightButton")!
        rightButton.frame = CGRect(
            x: dPadCenterX + dPadDist,
            y: dPadCenterY - rightButtonImage.size.height / 2,
            width: rightButtonImage.size.width,
            height: rightButtonImage.size.height
        )
        rightButton.contents = rightButtonImage.cgImage
        view.layer.addSublayer(rightButton)

        // Up button
        let upButtonImage = UIImage(named: "UpButton")!
        upButton.frame = CGRect(
            x: dPadCenterX - upButtonImage.size.width / 2,
            y: dPadCenterY - dPadDist - upButtonImage.size.height,
            width: upButtonImage.size.width,
            height: upButtonImage.size.height
        )
        upButton.contents = upButtonImage.cgImage
        view.layer.addSublayer(upButton)

        // Left button
        let leftButtonImage = UIImage(named: "LeftButton")!
        leftButton.frame = CGRect(
            x: dPadCenterX - dPadDist - leftButtonImage.size.width,
            y: dPadCenterY - leftButtonImage.size.height / 2,
            width: leftButtonImage.size.width,
            height: leftButtonImage.size.height
        )
        leftButton.contents = leftButtonImage.cgImage
        view.layer.addSublayer(leftButton)
    }

    private func drawStartSelect() {
        guard let view else { return }

        let startButtonImage = UIImage(named: "StartButton")!
        startButton.frame = CGRect(
            x: startX - startButtonImage.size.width / 2,
            y: startY - startButtonImage.size.height / 2,
            width: startButtonImage.size.width,
            height: startButtonImage.size.height
        )
        startButton.contents = startButtonImage.cgImage
        view.layer.addSublayer(startButton)

        let selectButtonImage = UIImage(named: "SelectButton")!
        selectButton.frame = CGRect(
            x: selectX - selectButtonImage.size.width / 2,
            y: selectY - selectButtonImage.size.height / 2,
            width: selectButtonImage.size.width,
            height: selectButtonImage.size.height
        )
        selectButton.contents = selectButtonImage.cgImage
        view.layer.addSublayer(selectButton)
    }

    private func drawBumpers() {
        guard let view else { return }

        let l1ButtonImage = UIImage(named: "L1")!
        l1Button.frame = CGRect(
            x: l1X - l1ButtonImage.size.width / 2,
            y: l1Y - l1ButtonImage.size.height / 2,
            width: l1ButtonImage.size.width,
            height: l1ButtonImage.size.height
        )
        l1Button.contents = l1ButtonImage.cgImage
        view.layer.addSublayer(l1Button)

        let r1ButtonImage = UIImage(named: "R1")!
        r1Button.frame = CGRect(
            x: r1X - r1ButtonImage.size.width / 2,
            y: r1Y - r1ButtonImage.size.height / 2,
            width: r1ButtonImage.size.width,
            height: r1ButtonImage.size.height
        )
        r1Button.contents = r1ButtonImage.cgImage
        view.layer.addSublayer(r1Button)
    }

    private func drawTriggers() {
        guard let view else { return }

        let l2ButtonImage = UIImage(named: "L2")!
        l2Button.frame = CGRect(
            x: l2X - l2ButtonImage.size.width / 2,
            y: l2Y - l2ButtonImage.size.height / 2,
            width: l2ButtonImage.size.width,
            height: l2ButtonImage.size.height
        )
        l2Button.contents = l2ButtonImage.cgImage
        view.layer.addSublayer(l2Button)

        let r2ButtonImage = UIImage(named: "R2")!
        r2Button.frame = CGRect(
            x: r2X - r2ButtonImage.size.width / 2,
            y: r2Y - r2ButtonImage.size.height / 2,
            width: r2ButtonImage.size.width,
            height: r2ButtonImage.size.height
        )
        r2Button.contents = r2ButtonImage.cgImage
        view.layer.addSublayer(r2Button)
    }

    private func drawSticks() {
        guard let view else { return }

        // Left analog stick
        let leftStickBgImage = UIImage(named: "StickOuter")!
        leftStickBackground.frame = CGRect(
            x: lsCenterX - leftStickBgImage.size.width / 2,
            y: lsCenterY - leftStickBgImage.size.height / 2,
            width: leftStickBgImage.size.width,
            height: leftStickBgImage.size.height
        )
        leftStickBackground.contents = leftStickBgImage.cgImage
        view.layer.addSublayer(leftStickBackground)

        let leftStickImage = UIImage(named: "StickInner")!
        leftStick.frame = CGRect(
            x: lsCenterX - leftStickImage.size.width / 2,
            y: lsCenterY - leftStickImage.size.height / 2,
            width: leftStickImage.size.width,
            height: leftStickImage.size.height
        )
        leftStick.contents = leftStickImage.cgImage
        view.layer.addSublayer(leftStick)

        // Right analog stick
        let rightStickBgImage = UIImage(named: "StickOuter")!
        rightStickBackground.frame = CGRect(
            x: rsCenterX - rightStickBgImage.size.width / 2,
            y: rsCenterY - rightStickBgImage.size.height / 2,
            width: rightStickBgImage.size.width,
            height: rightStickBgImage.size.height
        )
        rightStickBackground.contents = rightStickBgImage.cgImage
        view.layer.addSublayer(rightStickBackground)

        let rightStickImage = UIImage(named: "StickInner")!
        rightStick.frame = CGRect(
            x: rsCenterX - rightStickImage.size.width / 2,
            y: rsCenterY - rightStickImage.size.height / 2,
            width: rightStickImage.size.width,
            height: rightStickImage.size.height
        )
        rightStick.contents = rightStickImage.cgImage
        view.layer.addSublayer(rightStick)

        stickInnerSize = rightStickImage.size.width
        stickOuterSize = rightStickBgImage.size.width
    }

    private func drawL3R3() {
        guard let view else { return }

        let l3ButtonImage = UIImage(named: "L3")!
        l3Button.frame = CGRect(
            x: l3X - l3ButtonImage.size.width / 2,
            y: l3Y - l3ButtonImage.size.height / 2,
            width: l3ButtonImage.size.width,
            height: l3ButtonImage.size.height
        )
        l3Button.contents = l3ButtonImage.cgImage
        l3Button.cornerRadius = l3ButtonImage.size.width / 2
        l3Button.borderColor = UIColor(red: 15.0/255, green: 160.0/255, blue: 40.0/255, alpha: 1.0).cgColor
        view.layer.addSublayer(l3Button)

        let r3ButtonImage = UIImage(named: "R3")!
        r3Button.frame = CGRect(
            x: r3X - r3ButtonImage.size.width / 2,
            y: r3Y - r3ButtonImage.size.height / 2,
            width: r3ButtonImage.size.width,
            height: r3ButtonImage.size.height
        )
        r3Button.contents = r3ButtonImage.cgImage
        r3Button.cornerRadius = r3ButtonImage.size.width / 2
        r3Button.borderColor = UIColor(red: 15.0/255, green: 160.0/255, blue: 40.0/255, alpha: 1.0).cgColor
        view.layer.addSublayer(r3Button)
    }

    // MARK: - Hide helpers

    private func hideButtons() {
        aButton.removeFromSuperlayer()
        bButton.removeFromSuperlayer()
        xButton.removeFromSuperlayer()
        yButton.removeFromSuperlayer()
        upButton.removeFromSuperlayer()
        downButton.removeFromSuperlayer()
        leftButton.removeFromSuperlayer()
        rightButton.removeFromSuperlayer()
    }

    private func hideStartSelect() {
        startButton.removeFromSuperlayer()
        selectButton.removeFromSuperlayer()
    }

    private func hideBumpers() {
        l1Button.removeFromSuperlayer()
        r1Button.removeFromSuperlayer()
    }

    private func hideTriggers() {
        l2Button.removeFromSuperlayer()
        r2Button.removeFromSuperlayer()
    }

    private func hideSticks() {
        leftStickBackground.removeFromSuperlayer()
        rightStickBackground.removeFromSuperlayer()
        leftStick.removeFromSuperlayer()
        rightStick.removeFromSuperlayer()
    }

    private func hideL3R3() {
        l3Button.removeFromSuperlayer()
        r3Button.removeFromSuperlayer()
    }

    // MARK: - Touch Handling

    func handleTouchMovedEvent(_ touches: Set<UITouch>) -> Bool {
        guard let view else { return false }

        var updated = false
        var buttonTouch = false

        let rsMaxX = rsCenterX + stickOuterSize / 2
        let rsMaxY = rsCenterY + stickOuterSize / 2
        let rsMinX = rsCenterX - stickOuterSize / 2
        let rsMinY = rsCenterY - stickOuterSize / 2
        let lsMaxX = lsCenterX + stickOuterSize / 2
        let lsMaxY = lsCenterY + stickOuterSize / 2
        let lsMinX = lsCenterX - stickOuterSize / 2
        let lsMinY = lsCenterY - stickOuterSize / 2

        for touch in touches {
            let touchLocation = touch.location(in: view)
            var xLoc = touchLocation.x
            var yLoc = touchLocation.y

            if touch === lsTouch {
                if xLoc > lsMaxX { xLoc = lsMaxX }
                if xLoc < lsMinX { xLoc = lsMinX }
                if yLoc > lsMaxY { yLoc = lsMaxY }
                if yLoc < lsMinY { yLoc = lsMinY }

                leftStick.frame = CGRect(
                    x: xLoc - stickInnerSize / 2,
                    y: yLoc - stickInnerSize / 2,
                    width: stickInnerSize,
                    height: stickInnerSize
                )

                var xStickVal = Float((xLoc - lsCenterX) / (lsMaxX - lsCenterX))
                var yStickVal = Float((yLoc - lsCenterY) / (lsMaxY - lsCenterY))

                if fabsf(xStickVal) < stickDeadZone { xStickVal = 0 }
                if fabsf(yStickVal) < stickDeadZone { yStickVal = 0 }

                controllerSupport.updateLeftStick(controller,
                    x: Int16(Float(0x7FFE) * xStickVal),
                    y: Int16(Float(0x7FFE) * -yStickVal))

                updated = true
            } else if touch === rsTouch {
                if xLoc > rsMaxX { xLoc = rsMaxX }
                if xLoc < rsMinX { xLoc = rsMinX }
                if yLoc > rsMaxY { yLoc = rsMaxY }
                if yLoc < rsMinY { yLoc = rsMinY }

                rightStick.frame = CGRect(
                    x: xLoc - stickInnerSize / 2,
                    y: yLoc - stickInnerSize / 2,
                    width: stickInnerSize,
                    height: stickInnerSize
                )

                var xStickVal = Float((xLoc - rsCenterX) / (rsMaxX - rsCenterX))
                var yStickVal = Float((yLoc - rsCenterY) / (rsMaxY - rsCenterY))

                if fabsf(xStickVal) < stickDeadZone { xStickVal = 0 }
                if fabsf(yStickVal) < stickDeadZone { yStickVal = 0 }

                controllerSupport.updateRightStick(controller,
                    x: Int16(Float(0x7FFE) * xStickVal),
                    y: Int16(Float(0x7FFE) * -yStickVal))

                updated = true
            } else if touch === dpadTouch {
                controllerSupport.clearButtonFlag(controller,
                    flags: UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG)

                // Allow the user to slide their finger to another d-pad button
                if upButton.presentation()?.hitTest(touchLocation) != nil {
                    controllerSupport.setButtonFlag(controller, flags: UP_FLAG)
                    updated = true
                } else if downButton.presentation()?.hitTest(touchLocation) != nil {
                    controllerSupport.setButtonFlag(controller, flags: DOWN_FLAG)
                    updated = true
                } else if leftButton.presentation()?.hitTest(touchLocation) != nil {
                    controllerSupport.setButtonFlag(controller, flags: LEFT_FLAG)
                    updated = true
                } else if rightButton.presentation()?.hitTest(touchLocation) != nil {
                    controllerSupport.setButtonFlag(controller, flags: RIGHT_FLAG)
                    updated = true
                }

                buttonTouch = true
            } else if touch === aTouch
                || touch === bTouch
                || touch === xTouch
                || touch === yTouch
                || touch === startTouch
                || touch === selectTouch
                || touch === l1Touch
                || touch === r1Touch
                || touch === l2Touch
                || touch === r2Touch
                || touch === l3Touch
                || touch === r3Touch {
                buttonTouch = true
            }

            if deadTouches.contains(where: { $0 === touch }) {
                updated = true
            }
        }

        if updated {
            controllerSupport.updateFinished(controller)
        }
        return updated || buttonTouch
    }

    func handleTouchDownEvent(_ touches: Set<UITouch>) -> Bool {
        guard let view else { return false }

        var updated = false
        var stickTouch = false

        for touch in touches {
            let touchLocation = touch.location(in: view)

            if aButton.superlayer != nil, aButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: A_FLAG)
                aTouch = touch
                updated = true
            } else if bButton.superlayer != nil, bButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: B_FLAG)
                bTouch = touch
                updated = true
            } else if xButton.superlayer != nil, xButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: X_FLAG)
                xTouch = touch
                updated = true
            } else if yButton.superlayer != nil, yButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: Y_FLAG)
                yTouch = touch
                updated = true
            } else if upButton.superlayer != nil, upButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: UP_FLAG)
                dpadTouch = touch
                updated = true
            } else if downButton.superlayer != nil, downButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: DOWN_FLAG)
                dpadTouch = touch
                updated = true
            } else if leftButton.superlayer != nil, leftButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: LEFT_FLAG)
                dpadTouch = touch
                updated = true
            } else if rightButton.superlayer != nil, rightButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: RIGHT_FLAG)
                dpadTouch = touch
                updated = true
            } else if startButton.superlayer != nil, startButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: PLAY_FLAG)
                startTouch = touch
                updated = true
            } else if selectButton.superlayer != nil, selectButton.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: BACK_FLAG)
                selectTouch = touch
                updated = true
            } else if l1Button.superlayer != nil, l1Button.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: LB_FLAG)
                l1Touch = touch
                updated = true
            } else if r1Button.superlayer != nil, r1Button.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.setButtonFlag(controller, flags: RB_FLAG)
                r1Touch = touch
                updated = true
            } else if l2Button.superlayer != nil, l2Button.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.updateLeftTrigger(controller, left: 0xFF)
                l2Touch = touch
                updated = true
            } else if r2Button.superlayer != nil, r2Button.presentation()?.hitTest(touchLocation) != nil {
                controllerSupport.updateRightTrigger(controller, right: 0xFF)
                r2Touch = touch
                updated = true
            } else if l3Button.superlayer != nil, l3Button.presentation()?.hitTest(touchLocation) != nil {
                if l3Set {
                    controllerSupport.clearButtonFlag(controller, flags: LS_CLK_FLAG)
                    l3Button.borderWidth = 0.0
                } else {
                    controllerSupport.setButtonFlag(controller, flags: LS_CLK_FLAG)
                    l3Button.borderWidth = 2.0
                }
                l3Set.toggle()
                l3Touch = touch
                updated = true
            } else if r3Button.superlayer != nil, r3Button.presentation()?.hitTest(touchLocation) != nil {
                if r3Set {
                    controllerSupport.clearButtonFlag(controller, flags: RS_CLK_FLAG)
                    r3Button.borderWidth = 0.0
                } else {
                    controllerSupport.setButtonFlag(controller, flags: RS_CLK_FLAG)
                    r3Button.borderWidth = 2.0
                }
                r3Set.toggle()
                r3Touch = touch
                updated = true
            } else if leftStick.superlayer != nil, leftStick.presentation()?.hitTest(touchLocation) != nil {
                if let l3Start = l3TouchStart {
                    // Find elapsed time and convert to milliseconds
                    let l3TouchTime = -l3Start.timeIntervalSinceNow * 1000.0
                    if l3TouchTime < stickClickRate {
                        controllerSupport.setButtonFlag(controller, flags: LS_CLK_FLAG)
                        updated = true
                    }
                }
                lsTouch = touch
                stickTouch = true
            } else if rightStick.superlayer != nil, rightStick.presentation()?.hitTest(touchLocation) != nil {
                if let r3Start = r3TouchStart {
                    // Find elapsed time and convert to milliseconds
                    let r3TouchTime = -r3Start.timeIntervalSinceNow * 1000.0
                    if r3TouchTime < stickClickRate {
                        controllerSupport.setButtonFlag(controller, flags: RS_CLK_FLAG)
                        updated = true
                    }
                }
                rsTouch = touch
                stickTouch = true
            }

            if !updated && !stickTouch && isInDeadZone(touch) {
                deadTouches.append(touch)
                updated = true
            }
        }

        if updated {
            controllerSupport.updateFinished(controller)
        }
        return updated || stickTouch
    }

    func handleTouchUpEvent(_ touches: Set<UITouch>) -> Bool {
        var updated = false
        var touched = false

        for touch in touches {
            if touch === aTouch {
                controllerSupport.clearButtonFlag(controller, flags: A_FLAG)
                aTouch = nil
                updated = true
            } else if touch === bTouch {
                controllerSupport.clearButtonFlag(controller, flags: B_FLAG)
                bTouch = nil
                updated = true
            } else if touch === xTouch {
                controllerSupport.clearButtonFlag(controller, flags: X_FLAG)
                xTouch = nil
                updated = true
            } else if touch === yTouch {
                controllerSupport.clearButtonFlag(controller, flags: Y_FLAG)
                yTouch = nil
                updated = true
            } else if touch === dpadTouch {
                controllerSupport.clearButtonFlag(controller,
                    flags: UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG)
                dpadTouch = nil
                updated = true
            } else if touch === startTouch {
                controllerSupport.clearButtonFlag(controller, flags: PLAY_FLAG)
                startTouch = nil
                updated = true
            } else if touch === selectTouch {
                controllerSupport.clearButtonFlag(controller, flags: BACK_FLAG)
                selectTouch = nil
                updated = true
            } else if touch === l1Touch {
                controllerSupport.clearButtonFlag(controller, flags: LB_FLAG)
                l1Touch = nil
                updated = true
            } else if touch === r1Touch {
                controllerSupport.clearButtonFlag(controller, flags: RB_FLAG)
                r1Touch = nil
                updated = true
            } else if touch === l2Touch {
                controllerSupport.updateLeftTrigger(controller, left: 0)
                l2Touch = nil
                updated = true
            } else if touch === r2Touch {
                controllerSupport.updateRightTrigger(controller, right: 0)
                r2Touch = nil
                updated = true
            } else if touch === lsTouch {
                leftStick.frame = CGRect(
                    x: lsCenterX - stickInnerSize / 2,
                    y: lsCenterY - stickInnerSize / 2,
                    width: stickInnerSize,
                    height: stickInnerSize
                )
                controllerSupport.updateLeftStick(controller, x: 0, y: 0)
                controllerSupport.clearButtonFlag(controller, flags: LS_CLK_FLAG)
                l3TouchStart = Date()
                lsTouch = nil
                updated = true
            } else if touch === rsTouch {
                rightStick.frame = CGRect(
                    x: rsCenterX - stickInnerSize / 2,
                    y: rsCenterY - stickInnerSize / 2,
                    width: stickInnerSize,
                    height: stickInnerSize
                )
                controllerSupport.updateRightStick(controller, x: 0, y: 0)
                controllerSupport.clearButtonFlag(controller, flags: RS_CLK_FLAG)
                r3TouchStart = Date()
                rsTouch = nil
                updated = true
            } else if touch === l3Touch {
                l3Touch = nil
                touched = true
            } else if touch === r3Touch {
                r3Touch = nil
                touched = true
            }

            if let index = deadTouches.firstIndex(where: { $0 === touch }) {
                deadTouches.remove(at: index)
                updated = true
            }
        }

        if updated {
            controllerSupport.updateFinished(controller)
        }
        return updated || touched
    }

    // MARK: - Dead zone detection

    private func isInDeadZone(_ touch: UITouch) -> Bool {
        // Dynamically evaluate dead zones based on the controls on screen at the time
        if leftButton.superlayer != nil && isDpadDeadZone(touch) {
            return true
        } else if aButton.superlayer != nil && isAbxyDeadZone(touch) {
            return true
        } else if l2Button.superlayer != nil && isTriggerDeadZone(touch) {
            return true
        } else if l1Button.superlayer != nil && isBumperDeadZone(touch) {
            return true
        } else if startButton.superlayer != nil && isStartSelectDeadZone(touch) {
            return true
        } else if l3Button.superlayer != nil && isL3R3DeadZone(touch) {
            return true
        } else if leftStickBackground.superlayer != nil && isStickDeadZone(touch) {
            return true
        }
        return false
    }

    private func isDpadDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: view.frame.origin.x,
            startY: upButton.frame.origin.y,
            endX: rightButton.frame.origin.x + rightButton.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isAbxyDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: xButton.frame.origin.x,
            startY: yButton.frame.origin.y,
            endX: view.frame.origin.x + view.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isBumperDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: view.frame.origin.x,
            startY: l2Button.frame.origin.y + l2Button.frame.size.height,
            endX: l1Button.frame.origin.x + l1Button.frame.size.width,
            endY: upButton.frame.origin.y)
            || isDeadZone(touch,
            startX: r2Button.frame.origin.x,
            startY: r2Button.frame.origin.y + r2Button.frame.size.height,
            endX: view.frame.origin.x + view.frame.size.width,
            endY: yButton.frame.origin.y)
    }

    private func isTriggerDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: view.frame.origin.x,
            startY: l2Button.frame.origin.y,
            endX: l2Button.frame.origin.x + l2Button.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
            || isDeadZone(touch,
            startX: r2Button.frame.origin.x,
            startY: r2Button.frame.origin.y,
            endX: view.frame.origin.x + view.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isL3R3DeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: view.frame.origin.x,
            startY: l3Button.frame.origin.y,
            endX: view.frame.origin.x,
            endY: view.frame.origin.y + view.frame.size.height)
            || isDeadZone(touch,
            startX: r3Button.frame.origin.x,
            startY: r3Button.frame.origin.y,
            endX: view.frame.origin.x + view.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isStartSelectDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: startButton.frame.origin.x,
            startY: startButton.frame.origin.y,
            endX: view.frame.origin.x + view.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
            || isDeadZone(touch,
            startX: view.frame.origin.x,
            startY: selectButton.frame.origin.y,
            endX: selectButton.frame.origin.x + selectButton.frame.size.width,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isStickDeadZone(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        return isDeadZone(touch,
            startX: leftStickBackground.frame.origin.x - 15,
            startY: leftStickBackground.frame.origin.y - 15,
            endX: leftStickBackground.frame.origin.x + leftStickBackground.frame.size.width + 15,
            endY: view.frame.origin.y + view.frame.size.height)
            || isDeadZone(touch,
            startX: rightStickBackground.frame.origin.x - 15,
            startY: rightStickBackground.frame.origin.y - 15,
            endX: rightStickBackground.frame.origin.x + rightStickBackground.frame.size.width + 15,
            endY: view.frame.origin.y + view.frame.size.height)
    }

    private func isDeadZone(_ touch: UITouch, startX deadZoneStartX: CGFloat, startY deadZoneStartY: CGFloat, endX deadZoneEndX: CGFloat, endY deadZoneEndY: CGFloat) -> Bool {
        guard let view else { return false }
        let adjustedStartX = deadZoneStartX - deadZonePadding
        let adjustedStartY = deadZoneStartY - deadZonePadding
        let adjustedEndX = deadZoneEndX + deadZonePadding
        let adjustedEndY = deadZoneEndY + deadZonePadding

        let touchLocation = touch.location(in: view)
        return touchLocation.x > adjustedStartX && touchLocation.x < adjustedEndX
            && touchLocation.y > adjustedStartY && touchLocation.y < adjustedEndY
    }
}
