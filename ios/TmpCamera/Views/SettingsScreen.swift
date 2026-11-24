import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showIntro = false
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Delete photos after", selection: $model.lifetime) {
                        ForEach(Lifetime.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Delete photos after")
                } footer: {
                    Text("Applies to new photos.")
                }

                Section {
                    Toggle("Open straight to camera", isOn: $model.openToCamera)
                        .accessibilityIdentifier("open-to-camera")
                } footer: {
                    Text("Skip the home screen when the app opens.")
                }

                Section {
                    Button("Delete all photos now", role: .destructive) { confirmDeleteAll = true }
                        .disabled(model.ledger.shots.isEmpty)
                        .accessibilityIdentifier("delete-all")
                }

                Section {
                    Text("Photos stay in this app. No network access, no account, no ads, no analytics.")
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
            .confirmationDialog(deleteAllTitle, isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { model.deleteAll() }
                    .accessibilityIdentifier("confirm-delete-all")
            }
        }
        .sheet(isPresented: $showIntro) {
            IntroScreen(buttonTitle: "Done") { showIntro = false }
                .environmentObject(model)
        }
    }

    private var deleteAllTitle: String {
        let n = model.ledger.shots.count
        return n == 1 ? "Delete 1 photo now?" : "Delete all \(n) photos now?"
    }
}
