import SwiftUI

struct StatsOverlayView: View {
    let text: String

    var body: some View {
        VStack {
            Text(text)
                #if os(tvOS)
                .font(.system(size: 24))
                #else
                .font(.system(size: 12))
                #endif
                .foregroundStyle(.gray)
                .padding(6)
                .background(.black)
                .opacity(0.5)
            Spacer()
        }
    }
}
