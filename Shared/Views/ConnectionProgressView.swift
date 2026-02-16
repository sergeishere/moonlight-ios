import SwiftUI

struct ConnectionProgressView: View {
    let stageText: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                #if os(tvOS)
                .scaleEffect(2)
                #endif
            Text(stageText)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }
}
