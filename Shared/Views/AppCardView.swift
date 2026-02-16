import SwiftUI

struct AppCardView: View {
    let app: App
    let hostUUID: String

    @State private var boxArt: UIImage?

    var body: some View {
        Group {
            if let boxArt {
                boxArtContent(boxArt)
            } else {
                fallbackContent
            }
        }
        .frame(width: 195, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 20))
        .hoverEffect()
        .task(id: app.id) {
            boxArt = await BoxArtCache.shared.image(hostUUID: hostUUID, appId: app.id)
        }
    }

    private func boxArtContent(_ image: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 195, height: 260)

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(app.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var fallbackContent: some View {
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
