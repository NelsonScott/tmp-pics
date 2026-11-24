import SwiftUI
import UIKit

/// Full screen camera, presented from the home screen. The shutter saves and stays here for more shots;
/// the counter on the last-shot thumbnail confirms each save. Done (or the thumbnail) goes back home.
/// Always dark, like the system Camera, with the status bar hidden.
struct CameraScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var flash = false
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var shutterFlash = false
    @State private var front = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
            controls
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { toast }
        .environment(\.colorScheme, .dark)
        // Camera controls sit in fixed spots, like the system Camera; past this size they wrap and clip.
        // Every control keeps its VoiceOver label.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .statusBarHidden()
        .task { await model.cameraAppeared() }
        .onAppear {
            front = model.camera.position == .front
            setZoom(1)
        }
        .onDisappear { model.cameraDisappeared() }
        .alert("Photos access is off", isPresented: $model.photosOffAlert) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shots are saved to Photos, so the app needs access to save them.")
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .accessibilityIdentifier("camera-done")
            Spacer()
            if model.timeScale != 1 || model.camera.isMock {
                Text(model.camera.isMock ? "Test mode" : "Fast clock")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.yellow))
            }
            Spacer()
            if model.camera.hasFlash && !front {
                RoundIcon(systemName: flash ? "bolt.fill" : "bolt.slash", tint: flash ? .yellow : .white,
                          label: flash ? "Flash on" : "Flash off") { flash.toggle() }
                    .accessibilityIdentifier("flash")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
    }

    private var viewfinder: some View {
        // Full width, 3:4 like the photo it takes.
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    if model.camera.isMock {
                        MockPreview(zoom: zoom, front: front)
                    } else if model.cameraAccess == .granted, let real = model.camera as? RealCamera {
                        CameraPreview(camera: real)
                    } else {
                        cameraOff
                    }
                    if shutterFlash { Color.black.opacity(0.85) }
                }
            }
            .clipped()
        .contentShape(Rectangle())
        .gesture(pinch)
        .overlay(alignment: .bottom) { zoomPills.padding(.bottom, 12) }
    }

    private var zoomPills: some View {
        HStack(spacing: 6) {
            ForEach([CGFloat(1), 2], id: \.self) { level in
                let active = level == 1 ? zoom < 1.95 : zoom >= 1.95
                let exact = abs(zoom - level) < 0.05
                Button {
                    setZoom(level)
                } label: {
                    Text(active && !exact ? String(format: "%.1fx", zoom) : "\(Int(level))x")
                        .font(.caption.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .foregroundStyle(active ? Color.brightAccent : .white)
                }
                .accessibilityLabel("Zoom \(Int(level))x")
            }
        }
    }

    private var controls: some View {
        HStack {
            lastShot
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: 64, height: 64)
                }
            }
            .buttonStyle(ShutterStyle())
            .accessibilityLabel("Take photo")
            .accessibilityIdentifier("shutter")
            Spacer()
            RoundIcon(systemName: "arrow.triangle.2.circlepath", tint: .white, label: "Switch camera", size: 52) {
                model.camera.flip()
                front.toggle()
                setZoom(1)
            }
            .accessibilityIdentifier("flip")
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
        .animation(.spring(duration: 0.3), value: model.cameraSessionShots.count)
    }

    /// The newest shot from this visit, with how many were saved. Empty until the first save.
    @ViewBuilder private var lastShot: some View {
        let shots = model.cameraSessionShots
        if let last = shots.last {
            Button(action: close) {
                Thumbnail(id: last, pixels: 160)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1.5))
                    .overlay(alignment: .topTrailing) {
                        Text("\(shots.count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.black)
                            .frame(minWidth: 22, minHeight: 22)
                            .padding(.horizontal, shots.count > 9 ? 4 : 0)
                            .background(Capsule().fill(Color.brightAccent))
                            .offset(x: 8, y: -8)
                    }
                    .id(last)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .accessibilityLabel(shots.count == 1 ? "1 photo saved. Done" : "\(shots.count) photos saved. Done")
            .accessibilityValue("\(shots.count)")
            .accessibilityIdentifier("last-shot")
        } else {
            Color.clear.frame(width: 52, height: 52)
        }
    }

    private var cameraOff: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera").font(.largeTitle)
            Text(model.cameraAccess == .denied ? "Camera access is off" : "Starting camera")
                .font(.headline)
            if model.cameraAccess == .denied {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.18)))
                .padding(.top, 58)
                .transition(.opacity)
                .accessibilityIdentifier("toast")
        }
    }

    // MARK: Actions

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil { pinchStart = zoom }
                setZoom((pinchStart ?? 1) * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = max(1, min(value, model.camera.maxZoom))
        model.camera.setZoom(zoom)
    }

    private func shoot() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.05)) { shutterFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.15)) { shutterFlash = false }
        }
        Task {
            await model.shoot(flash: flash)
        }
    }

    private func close() {
        model.cameraOpen = false
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct RoundIcon: View {
    let systemName: String
    let tint: Color
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .accessibilityLabel(label)
    }
}

extension Color {
    /// The yellow fill behind black glyphs and text (camera button, Start, Clear, badges), in both modes.
    /// Text drawn in the accent uses AccentColor instead, which is darker in light mode for contrast.
    static let brightAccent = Color(red: 1, green: 0.78, blue: 0.18)
}

struct ShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
