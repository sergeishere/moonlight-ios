import SwiftUI

struct AppCardView: View {
    let app: App

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(app.name)
                .font(.title3.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .frame(width: 195, height: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
