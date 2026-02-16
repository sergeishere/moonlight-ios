import UIKit
import os

#if os(visionOS)
import AVFoundation
#endif

private let logger = Logger(subsystem: "Moonlight", category: "StreamHostController")

/// Thin UIViewController that hosts Metal rendering + input views and provides
/// system-level VC properties (pointer lock, home indicator, display mode).
/// All streaming logic lives in StreamViewModel.
final class StreamHostController: UIViewController {
    private let viewModel: StreamViewModel

    #if !os(visionOS)
    private var streamView: StreamView?
    #endif

    #if os(tvOS)
    private var menuTapRecognizer: UITapGestureRecognizer?
    private var menuDoubleTapRecognizer: UITapGestureRecognizer?
    private var playPauseTapRecognizer: UITapGestureRecognizer?
    #elseif !os(visionOS)
    private var exitSwipeRecognizer: UIScreenEdgePanGestureRecognizer?
    #endif

    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        #if os(visionOS)
        setupVisionOS()
        #else
        setupMetalAndInput()
        setupGestures()
        #endif

        // Observe viewModel changes for Metal/connection state
        setupObservation()
    }

    #if !os(visionOS)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfPrefersPointerLocked()
    }
    #endif

    // MARK: - visionOS Setup

    #if os(visionOS)
    private func setupVisionOS() {
        let displayLayer = viewModel.displayLayer
        displayLayer.frame = view.bounds
        view.layer.addSublayer(displayLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewModel.displayLayer.frame = view.bounds
    }
    #endif

    // MARK: - iOS/tvOS Setup

    #if !os(visionOS)
    private func setupMetalAndInput() {
        // Create StreamView (input layer)
        let sv = StreamView(frame: view.bounds)
        sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let cs = viewModel.controllerSupport {
            sv.setupStreamView(cs, interactionDelegate: self, config: viewModel.config)
        }
        view.addSubview(sv)
        streamView = sv

        // MetalViewController is added as child when connection starts (via observation)
    }

    private func setupGestures() {
        #if os(tvOS)
        let menuTap = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]

        let menuDoubleTap = UITapGestureRecognizer(target: self, action: #selector(menuDoublePressed))
        menuDoubleTap.numberOfTapsRequired = 2
        menuDoubleTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menuTap.require(toFail: menuDoubleTap)

        let playPauseTap = UITapGestureRecognizer(target: self, action: #selector(playPausePressed))
        playPauseTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]

        view.addGestureRecognizer(menuTap)
        view.addGestureRecognizer(menuDoubleTap)
        view.addGestureRecognizer(playPauseTap)

        menuTapRecognizer = menuTap
        menuDoubleTapRecognizer = menuDoubleTap
        playPauseTapRecognizer = playPauseTap
        #else
        let swipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwiped))
        swipe.edges = .left
        swipe.delaysTouchesBegan = false
        swipe.delaysTouchesEnded = false
        view.addGestureRecognizer(swipe)
        exitSwipeRecognizer = swipe
        #endif
    }

    private func addMetalViewController() {
        let metalVC = viewModel.metalViewController
        guard metalVC.parent == nil, let sv = streamView else { return }

        addChild(metalVC)
        sv.insertSubview(metalVC.view, at: 0)
        metalVC.view.frame = sv.bounds
        metalVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalVC.didMove(toParent: self)
    }
    #endif

    // MARK: - Observation

    private func setupObservation() {
        // Use withObservationTracking to react to ViewModel changes
        observeConnection()
    }

    private func observeConnection() {
        withObservationTracking {
            _ = viewModel.isConnected
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.viewModel.isConnected else {
                    self?.observeConnection()
                    return
                }
                self.handleConnectionStarted()
            }
        }
    }

    private func handleConnectionStarted() {
        #if !os(visionOS)
        addMetalViewController()
        streamView?.showOnScreenControls()
        #endif

        #if os(tvOS)
        updatePreferredDisplayMode(streamActive: true)
        #endif
    }

    // MARK: - tvOS Display Mode

    #if os(tvOS)
    func updatePreferredDisplayMode(streamActive: Bool) {
        // Private API for content matching on tvOS
        // Handled separately if needed
    }

    @objc private func menuPressed() {}

    @objc private func menuDoublePressed() {
        logger.info("Menu double-pressed -- backing out of stream")
        viewModel.dismiss()
    }

    @objc private func playPausePressed() {
        logger.info("Play/Pause button pressed -- backing out of stream")
        viewModel.dismiss()
    }
    #endif

    // MARK: - iOS Exit

    #if !os(tvOS) && !os(visionOS)
    @objc private func edgeSwiped() {
        logger.info("User swiped to end stream")
        viewModel.dismiss()
    }
    #endif

    // MARK: - System VC Properties

    #if !os(tvOS) && !os(visionOS)
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override var prefersHomeIndicatorAutoHidden: Bool {
        guard let cs = viewModel.controllerSupport,
              let sv = streamView else { return false }
        return cs.getConnectedGamepadCount() > 0
            && sv.getCurrentOscState() == .off
    }

    override var shouldAutorotate: Bool { true }
    override var prefersPointerLocked: Bool { true }
    #endif
}

// MARK: - UserInteractionDelegate

#if !os(visionOS)
extension StreamHostController: UserInteractionDelegate {
    func userInteractionBegan() {
        #if !os(tvOS)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        #endif
    }

    func userInteractionEnded() {
        #if !os(tvOS)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        #endif
    }
}
#endif
