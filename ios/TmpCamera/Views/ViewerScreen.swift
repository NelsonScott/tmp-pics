import SwiftUI

/// Full screen view of the app's shots. Swipe between them; Share, Save to Photos, Delete.
struct ViewerScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: Shot
    @State private var selection: String = ""
    @State private var images: [String: UIImage] = [:]
    @State private var confirmDelete = false
    @State private var saving = false

    private var shots: [Shot] { model.recent }
    private var current: Shot? { shots.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(shots) { shot in
                    ZStack {
                        if let image = images[shot.id] ?? model.quickImage(shot.id) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(shot.id)
                    .task(id: shot.file) { await load(shot) }
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
                            .accessibilityIdentifier("viewer-expiry")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .overlay(alignment: .top) { toast }
        .tint(.brightAccent)
        .onAppear { selection = start.id }
        // A shot can expire or be deleted while it is showing: move on, or close when none are left.
        .onChange(of: shots.map(\.id)) { _, ids in
            if !ids.contains(selection) { showNextOrClose() }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .hidden) {
            Button("Delete Photo", role: .destructive) {
                if let current { model.delete(current) }
            }
            .accessibilityIdentifier("confirm-delete")
        }
        .alert("Photos access is off", isPresented: $model.photosOffAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To save photos, let Tmp add to Photos in Settings.")
        }
        // A photo viewer reads best on black in both modes, and the status bar stays light.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var actionBar: some View {
        if let current {
            let saved = model.fileURL(current)
            HStack {
                if let saved {
                    // The original file, full size, exactly as the camera made it.
                    ShareLink(item: saved) {
                        BarLabel(title: "Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("share")
                } else {
                    BarLabel(title: "Share", systemImage: "square.and.arrow.up").opacity(0.4)
                }
                Button {
                    Task {
                        saving = true
                        await model.saveToPhotos(current)
                        saving = false
                    }
                } label: {
                    BarLabel(title: "Save to Photos", systemImage: "square.and.arrow.down")
                }
                .disabled(saved == nil || saving)
                .accessibilityIdentifier("save-to-photos")
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    BarLabel(title: "Delete", systemImage: "trash")
                }
                .tint(.red)
                .disabled(saved == nil)
                .accessibilityIdentifier("delete")
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(.bar)
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.2)))
                .padding(.top, 56)
                .transition(.opacity)
                .accessibilityIdentifier("toast")
        }
    }

    /// The photo at screen size, from the file. While a brand-new shot is still saving, its instant
    /// picture shows instead.
    private func load(_ shot: Shot) async {
        guard images[shot.id] == nil, !shot.file.isEmpty else { return }
        let screen = UIScreen.main
        let pixels = max(screen.bounds.width, screen.bounds.height) * screen.scale
        images[shot.id] = await model.store.displayImage(file: shot.file, maxPixels: pixels)
    }

    private func showNextOrClose() {
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
            Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
