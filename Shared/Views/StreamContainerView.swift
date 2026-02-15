#if !os(visionOS)
import SwiftUI

struct StreamContainerView: UIViewControllerRepresentable {
    let config: StreamConfiguration
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> StreamFrameViewController {
        let vc = StreamFrameViewController()
        vc.streamConfig = config
        return vc
    }

    func updateUIViewController(_ vc: StreamFrameViewController, context: Context) {}
}
#endif
