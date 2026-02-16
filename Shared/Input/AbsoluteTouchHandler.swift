import UIKit

final class AbsoluteTouchHandler: UIResponder {
    private let view: StreamView

    private var longPressTimer: Timer?
    private var lastTouchDown: UITouch?
    private var lastTouchDownLocation: CGPoint = .zero
    private var lastTouchUp: UITouch?
    private var lastTouchUpLocation: CGPoint = .zero

    private static let longPressDelay: TimeInterval = 0.650
    private static let longPressDelta: CGFloat = 0.01
    private static let doubleTapDelay: TimeInterval = 0.250
    private static let doubleTapDelta: CGFloat = 0.025

    init(view: StreamView) {
        self.view = view
        super.init()
    }

    @objc private func onLongPressStart(_ timer: Timer) {
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_RIGHT))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event, event.allTouches?.count == 1, let touch = touches.first else { return }

        let loc = touch.location(in: view)
        let bounds = view.bounds.size

        if let lastUp = lastTouchUp,
           touch.timestamp - lastUp.timestamp <= Self.doubleTapDelay,
           hypot((loc.x / bounds.width) - (lastTouchUpLocation.x / bounds.width),
                 (loc.y / bounds.height) - (lastTouchUpLocation.y / bounds.height)) <= Self.doubleTapDelta {
            // Within deadzone — don't reposition
        } else {
            view.updateCursorLocation(loc, isMouse: false)
        }

        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_LEFT))

        longPressTimer = Timer.scheduledTimer(timeInterval: Self.longPressDelay, target: self,
                                              selector: #selector(onLongPressStart(_:)), userInfo: nil, repeats: false)

        lastTouchDown = touch
        lastTouchDownLocation = loc
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event, event.allTouches?.count == 1, let touch = touches.first else { return }

        let loc = touch.location(in: view)
        let bounds = view.bounds.size

        if hypot((loc.x / bounds.width) - (lastTouchDownLocation.x / bounds.width),
                 (loc.y / bounds.height) - (lastTouchDownLocation.y / bounds.height)) > Self.longPressDelta {
            longPressTimer?.invalidate()
            longPressTimer = nil
        }

        view.updateCursorLocation(loc, isMouse: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event, event.allTouches?.count == touches.count else { return }

        longPressTimer?.invalidate()
        longPressTimer = nil

        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_RIGHT))

        lastTouchUp = touches.first
        if let t = lastTouchUp {
            lastTouchUpLocation = t.location(in: view)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
