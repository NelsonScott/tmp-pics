import Photos
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [String] = []
    @State private var newName = ""
    @State private var showIntro = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Photos expire after", selection: $model.lifetime) {
                        ForEach(Lifetime.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Photos expire after")
                } footer: {
                    Text("Applies to new shots. When photos expire, tap Clear and iOS asks you to confirm the delete.")
                }

                Section {
                    albumRows
                } header: {
                    Text("Album")
                } footer: {
                    Text("Only photos taken in this app are ever deleted. Other photos in the album are never touched.")
                }

                Section {
                    Toggle("Open straight to camera", isOn: $model.openToCamera)
                        .accessibilityIdentifier("open-to-camera")
                } footer: {
                    Text("Skip the home screen when the app opens.")
                }

                Section("Photos access") {
                    accessRow
                }

                Section {
                    Text("No network access, no account, no ads, no analytics. Your photos stay in your library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("How it works") { showIntro = true }
                        .accessibilityIdentifier("how-it-works")
                } header: {
                    Text("Privacy")
                }

                if QA.anyActive && !QA.demoPhotos {
                    Section("Testing") {
                        LabeledContent("Camera", value: model.camera.isMock ? "Mock" : "Real")
                        LabeledContent("Clock", value: model.timeScale == 1 ? "Normal" : "\(Int(model.timeScale))x faster")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settings-done")
                }
            }
            .onAppear(perform: loadAlbums)
        }
        .sheet(isPresented: $showIntro) {
            IntroScreen(buttonTitle: "Done") { showIntro = false }
                .environmentObject(model)
        }
    }

    @ViewBuilder private var albumRows: some View {
        if model.photoAccess == .full {
            let names = Array(Set(albums + [model.albumName])).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            ForEach(names, id: \.self) { name in
                Button {
                    model.albumName = name
                } label: {
                    HStack {
                        Text(name).foregroundStyle(Color.primary)
                        Spacer()
                        if name == model.albumName {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("album-\(name)")
            }
            newAlbumRow
        } else {
            LabeledContent("Saving to", value: model.albumName)
            newAlbumRow
            Text(model.photoAccess == .limited
                 ? "With limited access, iOS does not let apps use albums. Shots are still saved and cleared."
                 : "Allow Photos access to choose from your albums.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var newAlbumRow: some View {
        HStack {
            TextField("New album name", text: $newName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(useNewName)
            Button("Use", action: useNewName)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder private var accessRow: some View {
        switch model.photoAccess {
        case .full:
            LabeledContent("Status", value: "Full access")
        case .limited:
            LabeledContent("Status", value: "Limited")
            Button("Change in Settings", action: openSettings)
        case .notAsked:
            LabeledContent("Status", value: "Not asked yet")
            Button("Allow access") {
                Task {
                    await model.requestPhotoAccess()
                    loadAlbums()
                }
            }
        case .off:
            LabeledContent("Status", value: "Off")
            Button("Open Settings", action: openSettings)
        }
    }

    private func useNewName() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.albumName = name
        if !albums.contains(name) { albums.append(name) }
        newName = ""
    }

    private func loadAlbums() {
        model.refreshAccess()
        albums = PhotoLibrary.userAlbums().compactMap(\.localizedTitle)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
