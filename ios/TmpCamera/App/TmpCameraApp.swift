import SwiftUI

@main
struct TmpCameraApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onChange(of: phase, initial: true) { _, newPhase in
                    switch newPhase {
                    case .active: Task { await model.becameActive() }
                    case .background: model.resignedActive()
                    default: break
                    }
                }
        }
    }
}

/// First launch: the intro. After that: home, with the camera presented over it (straight away when
/// "Open straight to camera" is on).
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if model.introSeen {
                HomeScreen()
                    .transition(.opacity)
            } else {
                IntroScreen {
                    withAnimation(.easeInOut(duration: 0.25)) { model.finishIntro() }
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $model.cameraOpen) {
            CameraScreen()
                .environmentObject(model)
        }
    }
}
