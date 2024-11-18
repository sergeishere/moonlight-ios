//

import SwiftUI
import os.log

@main
struct MoonlightVisionApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appDelegate.mainViewModel)
        }
        .windowResizability(.contentSize)
        
        WindowGroup(id: "StreamWindow", for: CGSize.self) { screenSize in
            if let displaySize = screenSize.wrappedValue {
                StreamView()
                    .environmentObject(appDelegate.mainViewModel)
                    .onAppear {
                        let windowScenes = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                        guard let streamViewScene = windowScenes.first(where: {
                            guard let delegate = $0.delegate else { return false }
                            let mirror = Mirror(reflecting: delegate)
                            guard let sceneItemId = mirror.children.first(where: { $0.label == "sceneItemID" })
                            else { return false }
                            return String(describing: sceneItemId.value).contains("StreamWindow")
                        })
                        else { return }
                        
                        let scale = 2048 / displaySize.width
                        let scaledSize = displaySize.applying(.init(scaleX: scale, y: scale))
                        let geometry = UIWindowScene.GeometryPreferences.Vision(size: scaledSize, resizingRestrictions: .uniform)
                        streamViewScene.requestGeometryUpdate(geometry)
                        
                        do {
                            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(
                                .headTracked(
                                    soundStageSize: .automatic,
                                    anchoringStrategy: .scene(identifier: streamViewScene.session.persistentIdentifier)
                                )
                            )
                        } catch {
                            os_log(.error, "Unable to set spatial experience")
                        }
                    }
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
    }

}
