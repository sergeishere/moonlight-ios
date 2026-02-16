import UIKit
import os

#if os(visionOS)
import AVFoundation
#endif

private let logger = Logger(subsystem: "Moonlight", category: "StreamViewModel")

@Observable
@MainActor
final class StreamViewModel {
    // MARK: - Observable State

    var stageText: String
    var isConnected = false
    var isVideoShowing = false
    var statsText: String?
    var isHdrActive = false

    var alertTitle: String?
    var alertMessage: String?
    var showAlert = false

    // MARK: - Components

    let config: StreamConfiguration

    @ObservationIgnored
    private(set) var controllerSupport: ControllerSupport?
    @ObservationIgnored
    private(set) var streamSession: StreamSession?
    @ObservationIgnored
    private var onDismiss: (() -> Void)?
    @ObservationIgnored
    private var statsUpdateTimer: Timer?
    @ObservationIgnored
    private var inactivityTimer: Timer?

    // MARK: - Platform-specific rendering

    #if !os(visionOS)
    @ObservationIgnored
    let metalViewController: MetalViewController
    #else
    @ObservationIgnored
    let displayLayer = AVSampleBufferDisplayLayer()
    #endif

    // MARK: - Init

    init(config: StreamConfiguration, onDismiss: @escaping () -> Void) {
        self.config = config
        self.stageText = "Starting \(config.appName ?? "")..."
        self.onDismiss = onDismiss

        #if !os(visionOS)
        self.metalViewController = MetalViewController(
            frame: UIScreen.main.bounds,
            framerate: config.frameRate,
            enableHdr: false
        )
        #else
        displayLayer.videoGravity = .resizeAspect
        #endif
    }

    // MARK: - Lifecycle

    func startStream() {
        UIApplication.shared.isIdleTimerDisabled = true

        controllerSupport = ControllerSupport(config: config, delegate: self)

        #if os(visionOS)
        let session = StreamSession(
            config: config,
            videoRenderer: displayLayer.sampleBufferRenderer,
            delegate: self
        )
        #else
        let session = StreamSession(
            config: config,
            frameQueue: metalViewController.frameQueue,
            delegate: self
        )
        #endif

        streamSession = session
        session.start()
    }

    func stopStream() {
        statsUpdateTimer?.invalidate()
        statsUpdateTimer = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil

        streamSession?.stop()
        controllerSupport?.cleanup()
        #if !os(visionOS)
        metalViewController.shutdown()
        #endif

        UIApplication.shared.isIdleTimerDisabled = false
    }

    func dismiss() {
        stopStream()
        onDismiss?()
    }

    // MARK: - Stats

    private func startStatsTimer() {
        guard config.statsOverlay else { return }
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStats()
            }
        }
    }

    private func updateStats() {
        statsText = streamSession?.connection?.getStatsOverlayText()
    }

    // MARK: - Inactivity

    func applicationWillResignActive() {
        inactivityTimer?.invalidate()
        #if !os(tvOS)
        logger.info("Starting inactivity termination timer")
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                logger.info("Terminating stream after inactivity")
                self?.dismiss()
            }
        }
        #endif
    }

    func applicationDidBecomeActive() {
        if inactivityTimer != nil {
            logger.info("Stopping inactivity timer after becoming active again")
            inactivityTimer?.invalidate()
            inactivityTimer = nil
        }
    }

    func applicationDidEnterBackground() {
        logger.info("Terminating stream immediately for backgrounding")
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        dismiss()
    }

    // MARK: - Error presentation

    private func showError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - StreamConnectionDelegate

extension StreamViewModel: StreamConnectionDelegate {
    nonisolated func connectionStarted() {
        logger.info("Connection started")
        Task { @MainActor in
            isConnected = true
            stageText = ""

            #if !os(visionOS)
            controllerSupport?.connectionEstablished()
            #endif

            startStatsTimer()
        }
    }

    nonisolated func connectionTerminated(_ errorCode: Int32) {
        logger.info("Connection terminated: \(errorCode)")

        let portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode)
        let portTestResults = LiTestClientConnectivity("ios.conntest.moonlight-stream.org", 443, portFlags)

        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false

            if errorCode == ML_ERROR_GRACEFUL_TERMINATION {
                dismiss()
                return
            }

            let title: String
            let message: String

            if portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0 {
                title = "Connection Error"
                message = "Your device's network connection is blocking Moonlight. Streaming may not work while connected to this network."
            } else {
                switch errorCode {
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = "Connection Error"
                    var msg = "No video received from host."
                    if portFlags != 0 {
                        var failingPorts = [CChar](repeating: 0, count: 256)
                        LiStringifyPortFlags(portFlags, "\n", &failingPorts, 256)
                        msg += "\n\nCheck your firewall and port forwarding rules for port(s):\n\(String(cString: failingPorts))"
                    }
                    message = msg

                case ML_ERROR_NO_VIDEO_FRAME:
                    title = "Connection Error"
                    message = "Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection."

                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION, ML_ERROR_PROTECTED_CONTENT:
                    title = "Connection Error"
                    message = "Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC."

                case ML_ERROR_FRAME_CONVERSION:
                    title = "Connection Error"
                    message = "The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution."

                default:
                    let errorString = abs(errorCode) > 1000
                        ? String(format: "%08X", UInt32(bitPattern: errorCode))
                        : "\(errorCode)"
                    title = "Connection Terminated"
                    message = "The connection was terminated\n\nError code: \(errorString)"
                }
            }

            showError(title: title, message: message)
            streamSession?.stop()
        }
    }

    nonisolated func stageStarting(_ stageName: UnsafePointer<CChar>) {
        let name = String(cString: stageName)
        logger.info("Starting \(name)")
        Task { @MainActor in
            stageText = "\(name.prefix(1).uppercased())\(name.dropFirst()) in progress..."
        }
    }

    nonisolated func stageComplete(_ stageName: UnsafePointer<CChar>) {}

    nonisolated func stageFailed(_ stageName: UnsafePointer<CChar>, withError errorCode: Int32, portTestFlags: Int32) {
        let name = String(cString: stageName)
        logger.info("Stage \(name) failed: \(errorCode)")

        let portTestResults = LiTestClientConnectivity("ios.conntest.moonlight-stream.org", 443, UInt32(portTestFlags))

        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false

            var message = "\(name) failed with error \(errorCode)"
            if portTestFlags != 0 {
                var failingPorts = [CChar](repeating: 0, count: 256)
                LiStringifyPortFlags(UInt32(portTestFlags), "\n", &failingPorts, 256)
                message += "\n\nCheck your firewall and port forwarding rules for port(s):\n\(String(cString: failingPorts))"
            }
            if portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0 {
                message += "\n\nYour device's network connection is blocking Moonlight. Streaming may not work while connected to this network."
            }

            showError(title: "Connection Failed", message: message)
            streamSession?.stop()
        }
    }

    nonisolated func launchFailed(_ message: String) {
        logger.info("Launch failed: \(message)")
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
            showError(title: "Connection Error", message: message)
        }
    }

    nonisolated func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        Task { @MainActor in
            controllerSupport?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
        }
    }

    nonisolated func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {
        Task { @MainActor in
            controllerSupport?.rumbleTriggers(controllerNumber, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
        }
    }

    nonisolated func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {
        Task { @MainActor in
            controllerSupport?.setMotionEventState(controllerNumber, motionType: motionType, reportRateHz: reportRateHz)
        }
    }

    nonisolated func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {
        Task { @MainActor in
            controllerSupport?.setControllerLed(controllerNumber, r: r, g: g, b: b)
        }
    }

    nonisolated func connectionStatusUpdate(_ status: Int32) {
        Task { @MainActor in
            guard statsUpdateTimer == nil else { return }
            switch status {
            case CONN_STATUS_OKAY:
                statsText = nil
            case CONN_STATUS_POOR:
                statsText = config.bitRate > 5000
                    ? "Slow connection to PC\nReduce your bitrate"
                    : "Poor connection to PC"
            default: break
            }
        }
    }

    nonisolated func setHdrMode(_ enabled: Bool) {
        logger.info("HDR is now: \(enabled ? "active" : "inactive")")
        Task { @MainActor in
            isHdrActive = enabled
            #if !os(visionOS)
            metalViewController.setHdrEnabled(enabled)
            #endif
        }
    }

    nonisolated func videoContentShown() {
        Task { @MainActor in
            isVideoShowing = true
        }
    }
}

// MARK: - ControllerSupportDelegate

extension StreamViewModel: ControllerSupportDelegate {
    nonisolated func gamepadPresenceChanged() {
        // Handled by the hosting view controller
    }

    nonisolated func mousePresenceChanged() {
        // Handled by the hosting view controller
    }

    nonisolated func streamExitRequested() {
        logger.info("Gamepad combo requested stream exit")
        Task { @MainActor in
            dismiss()
        }
    }
}
