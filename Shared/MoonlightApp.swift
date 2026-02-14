import SwiftUI
import SwiftData
import AVFoundation

@main
struct MoonlightApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            HostListView()
        }
        .modelContainer(for: [Host.self, App.self, StreamSettings.self])
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
