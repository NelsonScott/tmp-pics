import SwiftUI

/// Full screen view of the app's own shots. Swipe between them; Share, Keep or Delete now.
struct ViewerScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: Shot
    @State private var selection: String = ""
    @State private var images: [String: UIImage] = [:]
    @State private var deleting = false

    private var shots: [Shot] { model.recent }
    private var current: Shot? { shots.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(shots) { shot in
                    ZStack {
                        if let image = images[shot.id] {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(shot.id)
                    .task { await load(shot.id) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("viewer-done")
                }
                ToolbarItem(placement: .principal) {
                    if let current {
                        Text(remainingPhrase(model.remaining(current)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.remaining(current) <= 0 ? Color.brightAccent : .primary)
                            .accessibilityIdentifier("viewer-expiry")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.brightAccent)
        .onAppear { selection = start.id }
        // A photo viewer reads best on black in both modes, and the status bar stays light.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var actionBar: some View {
        if let current {
            HStack {
                if let image = images[current.id] {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) {
                        BarLabel(title: "Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("share")
                } else {
                    BarLabel(title: "Share", systemImage: "square.and.arrow.up").opacity(0.4)
                }
                Button {
                    model.keep(current)
                    afterRemoval()
                } label: {
                    BarLabel(title: "Keep", systemImage: "pin")
                }
                .accessibilityIdentifier("keep")
                Button(role: .destructive) {
                    Task {
                        deleting = true
                        if await model.deleteNow(current) { afterRemoval() }
                        deleting = false
                    }
                } label: {
                    BarLabel(title: "Delete", systemImage: "trash")
                }
                .tint(.red)
                .disabled(deleting)
                .accessibilityIdentifier("delete")
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(.bar)
        }
    }

    private func load(_ id: String) async {
        guard images[id] == nil else { return }
        let scale = UIScreen.main.scale
        let size = CGSize(width: UIScreen.main.bounds.width * scale, height: UIScreen.main.bounds.height * scale)
        images[id] = await model.library.image(for: id, size: size, contentMode: .aspectFit)
    }

    /// After Keep or Delete the shot leaves the list: show the next one, or close when none are left.
    private func afterRemoval() {
        if let next = shots.first {
            selection = next.id
        } else {
            dismiss()
        }
    }
}

/// Icon over a short word, one third of the bar wide.
private struct BarLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3)
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
