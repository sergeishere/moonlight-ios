import SwiftUI

struct StreamContainerView: UIViewControllerRepresentable {
    let config: StreamConfiguration
    @Environment(\.dismiss) private var dismiss

    #if os(visionOS)
    func makeUIViewController(context: Context) -> VisionStreamViewController {
        let vc = VisionStreamViewController()
        vc.streamConfig = config
        vc.onDismiss = { [dismiss] in
            dismiss()
        }
        return vc
    }

    func updateUIViewController(_ vc: VisionStreamViewController, context: Context) {}
    #else
    func makeUIViewController(context: Context) -> StreamFrameViewController {
        let vc = StreamFrameViewController()
        vc.streamConfig = config
        vc.onDismiss = { [dismiss] in
            dismiss()
        }
        return vc
    }

    func updateUIViewController(_ vc: StreamFrameViewController, context: Context) {}
    #endif
}
