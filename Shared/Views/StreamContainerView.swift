import SwiftUI

struct StreamContainerView: View {
    let config: StreamConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StreamViewModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let viewModel {
                StreamHostView(viewModel: viewModel)

                if !viewModel.isVideoShowing {
                    ConnectionProgressView(stageText: viewModel.stageText)
                }

                if let stats = viewModel.statsText {
                    StatsOverlayView(text: stats)
                }
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .alert(
            viewModel?.alertTitle ?? "Error",
            isPresented: Binding(
                get: { viewModel?.showAlert ?? false },
                set: { viewModel?.showAlert = $0 }
            )
        ) {
            Button("OK") { dismiss() }
        } message: {
            Text(viewModel?.alertMessage ?? "")
        }
        .onAppear {
            let vm = StreamViewModel(config: config, onDismiss: { dismiss() })
            viewModel = vm
            vm.startStream()
        }
        .onDisappear {
            viewModel?.stopStream()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel?.applicationWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel?.applicationDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel?.applicationDidEnterBackground()
        }
    }
}

// MARK: - Platform Host View

/// Wraps the platform-specific UIViewController that provides system-level integration
/// (pointer lock, home indicator, Metal rendering, input handling).
private struct StreamHostView: UIViewControllerRepresentable {
    let viewModel: StreamViewModel

    func makeUIViewController(context: Context) -> StreamHostController {
        StreamHostController(viewModel: viewModel)
    }

    func updateUIViewController(_ controller: StreamHostController, context: Context) {}
}
