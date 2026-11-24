import SwiftUI

/// The app's current shots on the home screen, newest first, each with its time left. Tap one to open it.
struct ShotGrid: View {
    @EnvironmentObject private var model: AppModel
    @Binding var viewing: Shot?
    @ScaledMetric(relativeTo: .body) private var minTile: CGFloat = 104

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minTile), spacing: 8)], spacing: 8) {
            ForEach(model.recent) { shot in
                let remaining = model.remaining(shot)
                Button { viewing = shot } label: {
                    GridTile(id: shot.id, remaining: remaining)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shot")
                .accessibilityLabel("Photo, \(remainingPhrase(remaining))")
            }
        }
    }
}

/// Square thumbnail with a time-left chip in the corner. Expired shots are dimmed with a yellow chip.
private struct GridTile: View {
    let id: String
    let remaining: TimeInterval

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { Thumbnail(id: id, pixels: 360) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(remaining <= 0 ? 0.5 : 1)
            .overlay(alignment: .bottomLeading) {
                Text(remainingLabel(remaining))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(remaining <= 0 ? .black : .white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(remaining <= 0 ? Color.brightAccent : Color.black.opacity(0.6)))
                    .padding(6)
            }
            .contentShape(Rectangle())
    }
}

/// A shot's image from Photos, filling its frame. Grey until it loads.
struct Thumbnail: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    var pixels: CGFloat = 174
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .task(id: id) {
            image = await model.library.image(for: id, size: CGSize(width: pixels, height: pixels))
        }
    }
}
