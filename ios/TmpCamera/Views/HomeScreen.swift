import SwiftUI

/// The first screen on every launch: the app's current shots, a summary line, and one big camera button in
/// thumb reach. Expired shots simply disappear from the grid. Follows light and dark mode; its background
/// matches the launch screen.
struct HomeScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var viewing: Shot?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = model.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("summary")
                    }
                    if model.recent.isEmpty {
                        emptyState
                    } else {
                        ShotGrid(viewing: $viewing)
                    }
                }
                .padding(.horizontal, 16)   // lines up with the large title
                .padding(.bottom, 24)
                .animation(.default, value: model.shotCount)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { cameraButton }
            .navigationTitle("Tmp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings")
                }
            }
            .overlay(alignment: .top) { HomeToast() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen()
                .environmentObject(model)
        }
        .fullScreenCover(item: $viewing) { shot in
            ViewerScreen(start: shot)
                .environmentObject(model)
        }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Nothing here yet")
                .font(.title3.weight(.semibold))
            Text(emptyDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-empty")
    }

    private var emptyDetail: String {
        model.lifetime == .never
            ? "Photos you take stay here. Pick how long they last in Settings."
            : "Photos you take stay here and delete themselves after \(model.lifetime.label)."
    }

    /// Round, filled, lower middle: the one thing to do here.
    private var cameraButton: some View {
        Button { model.cameraOpen = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.brightAccent))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                Text("Take a photo")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .background(Color(.systemBackground))
        .accessibilityLabel("Take a photo")
        .accessibilityIdentifier("open-camera")
    }
}

/// The model's short messages, shown under the navigation bar.
private struct HomeToast: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let message = model.toast, !model.cameraOpen {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color(.label).opacity(0.88)))
                .padding(.top, 8)
                .transition(.opacity)
                .accessibilityIdentifier("toast")
        }
    }
}

/// Shrinks a little while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
