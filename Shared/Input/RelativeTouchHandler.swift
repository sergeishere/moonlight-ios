import UIKit

final class RelativeTouchHandler: UIResponder {
    private let view: UIView
    private var touchLocation: CGPoint = .zero
    private var originalLocation: CGPoint = .zero
    private var touchMoved = false
    private var isDragging = false
    private var dragTimer: Timer?
    private var peakTouchCount: Int = 0

    #if os(tvOS)
    private var remotePressRecognizer: UIGestureRecognizer?
    private var remoteLongPressRecognizer: UIGestureRecognizer?
    #endif

    private static let referenceWidth: CGFloat = 1280
    private static let referenceHeight: CGFloat = 720

    init(view: StreamView) {
        self.view = view
        super.init()

        #if os(tvOS)
        let tap = UITapGestureRecognizer(target: self, action: #selector(remoteButtonPressed(_:)))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(remoteButtonLongPressed(_:)))
        longPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        remotePressRecognizer = tap
        remoteLongPressRecognizer = longPress
        #endif
    }

    private func isConfirmedMove(_ current: CGPoint, from original: CGPoint) -> Bool {
        hypot(original.x - current.x, original.y - current.y) >= 5
    }

    @objc private func onDragStart(_ timer: Timer) {
        if !touchMoved && !isDragging {
            isDragging = true
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_LEFT))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        let allCount = event.allTouches?.count ?? 0
        touchMoved = false
        peakTouchCount = allCount

        if allCount == 1, let touch = event.allTouches?.first {
            originalLocation = touch.location(in: view)
            touchLocation = originalLocation
            if !isDragging {
                dragTimer = Timer.scheduledTimer(timeInterval: 0.650, target: self,
                                                 selector: #selector(onDragStart(_:)), userInfo: nil, repeats: false)
            }
        } else if allCount == 2, let all = event.allTouches?.sorted(by: { $0.hashValue < $1.hashValue }) {
            let first = all[0].location(in: view)
            let second = all[1].location(in: view)
            originalLocation = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
            touchLocation = originalLocation
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        let allCount = event.allTouches?.count ?? 0

        if allCount == 1, let touch = event.allTouches?.first {
            let current = touch.location(in: view)
            guard touchLocation != current else { return }

            let deltaX = Int16((current.x - touchLocation.x) * (Self.referenceWidth / view.bounds.width))
            let deltaY = Int16((current.y - touchLocation.y) * (Self.referenceHeight / view.bounds.height))

            if deltaX != 0 || deltaY != 0 {
                LiSendMouseMoveEvent(deltaX, deltaY)
                touchLocation = current
                if isConfirmedMove(touchLocation, from: originalLocation) {
                    touchMoved = true
                }
            }
        } else if allCount == 2, let all = event.allTouches?.sorted(by: { $0.hashValue < $1.hashValue }) {
            let first = all[0].location(in: view)
            let second = all[1].location(in: view)
            let avg = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)

            if touchLocation.y != avg.y {
                LiSendHighResScrollEvent(Int16((avg.y - touchLocation.y) * 10))
            }
            if isConfirmedMove(first, from: originalLocation) {
                touchMoved = true
            }
            touchLocation = avg
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        dragTimer?.invalidate()
        dragTimer = nil

        if isDragging {
            isDragging = false
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        } else if !touchMoved {
            if peakTouchCount == 2 {
                DispatchQueue.global(qos: .userInitiated).async {
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_RIGHT))
                    usleep(100_000)
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_RIGHT))
                }
            } else if peakTouchCount == 1 {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self else { return }
                    if !self.isDragging {
                        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_LEFT))
                        usleep(100_000)
                    }
                    self.isDragging = false
                    LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
                }
            }
        }

        // Synchronize finger position when going from 2+ to 1 touch
        let allCount = event.allTouches?.count ?? 0
        if allCount - touches.count == 1, let remaining = event.allTouches?.subtracting(touches).first {
            touchLocation = remaining.location(in: view)
            touchMoved = true
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragTimer?.invalidate()
        dragTimer = nil
        if isDragging {
            isDragging = false
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        }
        peakTouchCount = 0
    }

    #if os(tvOS)
    @objc private func remoteButtonPressed(_ sender: Any) {
        touchMoved = true
        DispatchQueue.global(qos: .userInitiated).async {
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_LEFT))
            usleep(100_000)
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), Int32(BUTTON_LEFT))
        }
    }

    @objc private func remoteButtonLongPressed(_ sender: Any) {
        isDragging = true
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_PRESS), Int32(BUTTON_LEFT))
    }
    #endif
}
