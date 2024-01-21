//
//  StreamViewModel.swift
//  Moonlight
//

import RealityKit
import AVKit
import os.log

final class ControllerSupportDelegateImpl: NSObject, ControllerSupportDelegate {
    
    func gamepadPresenceChanged() {
        os_log("gamepadPresenceChanged")
    }
    
    func mousePresenceChanged() {
        os_log("mousePresenceChanged")
    }
    
    func streamExitRequested() {
        os_log("streamExitRequested")
    }

}

final class ConnectionCallbacksImpl: NSObject, ConnectionCallbacks {
    
    weak var model: MainViewModel?
    
    func connectionStarted() {
        os_log(.info, "Connection started")
        model?.updateStatus(nil)
        model?.controllerSupport?.connectionEstablished()
    }
    
    func connectionTerminated(_ errorCode: Int32) {
        os_log(.info, "Connection terminated")
        
        // TODO: - handle
        Task {
            await model?.stopStream()
        }
    }
    
    func stageStarting(_ stageName: UnsafePointer<CChar>!) {
        let stageName = String(cString: stageName)
        os_log(.info, "Starting %s", stageName)
        
        model?.updateStatus("\(stageName) in progress...")
    }
    
    func stageComplete(_ stageName: UnsafePointer<CChar>!) {
        let stageName = String(cString: stageName)
        os_log(.info, "Stage %s complete", stageName)
    }
    
    func stageFailed(_ stageName: UnsafePointer<CChar>!, withError errorCode: Int32, portTestFlags: Int32) {
        let stageName = String(cString: stageName)
        os_log(.info, "Stage %s failed: %d", stageName, errorCode)
        
        // TODO: - handle
    }
    
    func launchFailed(_ message: String!) {
        os_log(.info, "Launch failed:", message)
    }
    
    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        os_log(.info, "Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor)
        model?.controllerSupport?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
    }
    
    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {
        os_log(.info, "Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger)
        model?.controllerSupport?.rumbleTriggers(controllerNumber, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
    }
    
    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {
        os_log(.info, "Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz)
        model?.controllerSupport?.setMotionEventState(controllerNumber, motionType: motionType, reportRateHz: reportRateHz)
    }
    
    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {
        os_log(.info, "Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b)
        model?.controllerSupport?.setControllerLed(controllerNumber, r: r, g: g, b: b)
    }
    
    func connectionStatusUpdate(_ status: Int32) {
        os_log(.debug, "Connection status update: %d", status)
        guard let model else { return }
        
        if status == CONN_STATUS_POOR {
            Task {
                if await model.currentStreamConfig.bitRate > 5000 {
                    model.updateStatus("Slow connection to PC. Reduce your bitrate")
                } else {
                    model.updateStatus("Poor connection to PC")
                }
            }
        }
    }
    
    func setHdrMode(_ enabled: Bool) {}
    
    func videoContentShown() {
        model?.updateStatus(nil)
    }
    
}
