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
                    GridTile(shot: shot, remaining: remaining)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shot")
                .accessibilityLabel("Photo, \(remainingPhrase(remaining))")
            }
        }
    }
}

/// Square thumbnail with a time-left chip in the corner (none for a shot that never expires).
private struct GridTile: View {
    let shot: Shot
    let remaining: TimeInterval?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { Thumbnail(id: shot.id, file: shot.file) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let label = remainingLabel(remaining) {
                    Text(label)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
    }
}

/// A shot's thumbnail, filling its frame. It shows in the same frame the shutter is pressed: the real
/// thumbnail if it is in memory, else the instant picture from the shutter, else a grey square that fades
/// to the image. `file` is empty while the shot is still saving; once it is set, the real thumbnail
/// replaces the stand-in (same picture, so nothing flickers).
struct Thumbnail: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    let file: String
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? model.quickImage(id)
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: image == nil)
        .task(id: file) {
            guard !file.isEmpty else { return }
            if let thumb = await model.store.thumbnail(id: id, file: file) { loaded = thumb }
        }
    }
}
