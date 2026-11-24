import SwiftUI

/// The first screen on every launch: the app's current shots, a summary line, the expired banner, and one
/// big camera button in thumb reach. Follows light and dark mode; its background matches the launch screen.
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
                    albumAccessBanner
                    expiredBanner
                    if model.recent.isEmpty {
                        emptyState
                    } else {
                        ShotGrid(viewing: $viewing)
                    }
                }
                .padding(.horizontal, 16)   // lines up with the large title
                .padding(.bottom, 24)
                .animation(.default, value: model.expiredCount)
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
            ? "Photos you take go to \(model.albumName). Pick how long they last in Settings."
            : "Photos you take go to \(model.albumName) and expire after \(model.lifetime.label)."
    }

    /// Limited Photos access: shots are saved but iOS will not let the app use the album. One calm, lasting
    /// note with the fix, instead of a message that flashes by in the camera.
    @ViewBuilder private var albumAccessBanner: some View {
        if model.photoAccess == .limited {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photos are saved, but not in your \(model.albumName) album yet.")
                    .font(.subheadline.weight(.medium))
                Text("In Settings, tap Photos and choose Full Access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.brightAccent))
                }
                .accessibilityIdentifier("album-access-settings")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("album-access-banner")
        }
    }

    @ViewBuilder private var expiredBanner: some View {
        let count = model.expiredCount
        if count > 0 {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.xmark")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(count == 1 ? "1 expired photo" : "\(count) expired photos")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await model.clearExpired() }
                } label: {
                    Text(model.isClearing ? "Clearing" : "Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.brightAccent))
                }
                .disabled(model.isClearing)
                .accessibilityIdentifier("clear")
            }
            .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("expired-banner")
            .transition(.opacity)
        }
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

/// The model's short messages ("Cleared 2 photos"), shown under the navigation bar.
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
