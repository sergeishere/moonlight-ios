import Foundation
import CoreHaptics
import GameController
import os

final class HapticContext {
    private let playerIndex: GCControllerPlayerIndex
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: (any CHHapticPatternPlayer)?
    private var playing = false

    private static let logger = Logger(subsystem: "Moonlight", category: "HapticContext")

    private init?(gamepad: GCController, locality: GCHapticsLocality) {
        guard let haptics = gamepad.haptics else {
            Self.logger.warning("Controller \(gamepad.playerIndex.rawValue) does not support haptics")
            return nil
        }
        guard haptics.supportedLocalities.contains(locality) else {
            Self.logger.warning("Controller \(gamepad.playerIndex.rawValue) does not support haptic locality: \(locality.rawValue)")
            return nil
        }

        self.playerIndex = gamepad.playerIndex

        guard let engine = haptics.createEngine(withLocality: locality) else {
            Self.logger.warning("Controller \(gamepad.playerIndex.rawValue): Failed to create haptic engine")
            return nil
        }
        self.hapticEngine = engine

        do {
            try engine.start()
        } catch {
            Self.logger.warning("Controller \(self.playerIndex.rawValue): Haptic engine failed to start: \(error)")
            return nil
        }

        engine.stoppedHandler = { [weak self] reason in
            guard let self else { return }
            Self.logger.warning("Controller \(self.playerIndex.rawValue): Haptic engine stopped: \(String(describing: reason))")
            self.hapticPlayer = nil
            self.hapticEngine = nil
            self.playing = false
        }

        engine.resetHandler = { [weak self] in
            guard let self else { return }
            Self.logger.warning("Controller \(self.playerIndex.rawValue): Haptic engine reset")
            self.hapticPlayer = nil
            self.playing = false
            try? self.hapticEngine?.start()
        }
    }

    func setMotorAmplitude(_ amplitude: UInt16) {
        guard hapticEngine != nil else { return }

        if amplitude == 0 {
            if playing {
                try? hapticPlayer?.stop(atTime: 0)
                playing = false
            }
            return
        }

        if hapticPlayer == nil {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity], relativeTime: 0, duration: TimeInterval(GCHapticDurationInfinite))
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
                  let player = try? hapticEngine?.makePlayer(with: pattern) else {
                Self.logger.warning("Controller \(self.playerIndex.rawValue): Haptic player creation failed")
                return
            }
            hapticPlayer = player
        }

        let param = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(amplitude) / 65535.0, relativeTime: 0)
        try? hapticPlayer?.sendParameters([param], atTime: CHHapticTimeImmediate)

        if !playing {
            do {
                try hapticPlayer?.start(atTime: 0)
                playing = true
            } catch {
                hapticPlayer = nil
                Self.logger.warning("Controller \(self.playerIndex.rawValue): Haptic playback start failed: \(error)")
            }
        }
    }

    func cleanup() {
        try? hapticPlayer?.cancel()
        hapticPlayer = nil
        hapticEngine?.stop(completionHandler: nil)
        hapticEngine = nil
    }

    // MARK: - Factory methods

    static func createForHighFreqMotor(_ gamepad: GCController) -> HapticContext? {
        HapticContext(gamepad: gamepad, locality: .rightHandle)
    }

    static func createForLowFreqMotor(_ gamepad: GCController) -> HapticContext? {
        HapticContext(gamepad: gamepad, locality: .leftHandle)
    }

    static func createForLeftTrigger(_ gamepad: GCController) -> HapticContext? {
        HapticContext(gamepad: gamepad, locality: .leftTrigger)
    }

    static func createForRightTrigger(_ gamepad: GCController) -> HapticContext? {
        HapticContext(gamepad: gamepad, locality: .rightTrigger)
    }
}
