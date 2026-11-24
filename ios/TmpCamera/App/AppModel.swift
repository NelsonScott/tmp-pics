import Photos
import SwiftUI

/// App state: settings, the ledger of tracked shots, and the actions the screens call.
@MainActor
final class AppModel: ObservableObject {
    static let defaultAlbum = "Tmp"

    @Published private(set) var ledger: Ledger
    @Published private(set) var now = Date()
    @Published var lifetime: Lifetime { didSet { defaults.set(lifetime.rawValue, forKey: Keys.lifetime) } }
    @Published var albumName: String { didSet { defaults.set(albumName, forKey: Keys.album) } }
    /// The one-screen intro has been seen (it shows once, then from Settings > How it works).
    @Published private(set) var introSeen: Bool { didSet { defaults.set(introSeen, forKey: Keys.introSeen) } }
    /// Settings: skip the home screen and open on the camera. Off by default.
    @Published var openToCamera: Bool { didSet { defaults.set(openToCamera, forKey: Keys.openToCamera) } }
    /// The full screen camera is showing.
    @Published var cameraOpen = false
    /// Shots saved since the camera last opened, newest last, for the camera's counter and thumbnail.
    @Published private(set) var cameraSessionShots: [String] = []
    @Published private(set) var photoAccess: PhotoLibrary.Access
    @Published private(set) var cameraAccess: CameraAccess
    @Published private(set) var isClearing = false
    @Published var toast: String?
    @Published var photosOffAlert = false

    let library = PhotoLibrary()
    let camera: Camera
    let timeScale = QA.timeScale
    private let file: LedgerFile
    private let defaults: UserDefaults
    private var ticker: Timer?
    private var toastTask: Task<Void, Never>?
    private var seeded = false

    private enum Keys {
        static let lifetime = "lifetime"
        static let album = "albumName"
        static let introSeen = "introSeen"
        static let openToCamera = "openToCamera"
    }

    init(file: LedgerFile = .standard, defaults: UserDefaults = .standard) {
        if QA.reset {
            file.reset()
            QALog.reset()
            defaults.removeObject(forKey: Keys.lifetime)
            defaults.removeObject(forKey: Keys.album)
            defaults.removeObject(forKey: Keys.introSeen)
            defaults.removeObject(forKey: Keys.openToCamera)
        }
        self.file = file
        self.defaults = defaults
        ledger = file.load()
        lifetime = QA.lifetime ?? defaults.string(forKey: Keys.lifetime).flatMap(Lifetime.init(rawValue:)) ?? .default
        albumName = defaults.string(forKey: Keys.album) ?? Self.defaultAlbum
        introSeen = defaults.bool(forKey: Keys.introSeen)
        openToCamera = defaults.bool(forKey: Keys.openToCamera)
        photoAccess = library.access
        cameraAccess = CameraAccess.current
        camera = QA.mockCamera ? MockCamera() : RealCamera()
        cameraOpen = introSeen && openToCamera
        QALog.write("launch mock=\(QA.mockCamera) scale=\(timeScale) tracked=\(ledger.shots.count)")
    }

    // MARK: Derived

    var recent: [Shot] { ledger.recent(at: now) }
    var expiredCount: Int { ledger.expired(at: now).count }
    func remaining(_ shot: Shot) -> TimeInterval { shot.remaining(at: now) }
    var summary: String? { ledger.summary(at: now) }

    // MARK: Lifecycle

    /// Called when the app comes to the front. Asks for nothing: camera access is asked when the camera
    /// first opens, Photos access on the first shot. With camera access already granted, the session is
    /// configured in the background so the camera opens quickly; it only runs while the camera is showing.
    func becameActive() async {
        photoAccess = library.access
        cameraAccess = CameraAccess.current
        if cameraOpen, camera.isMock || cameraAccess == .granted {
            camera.start()   // back from the background with the camera showing
        } else if cameraAccess == .granted {
            camera.prepare()
        }
        startTicker()
        reconcile()
        await seedIfAsked()
    }

    /// The camera screen is showing (or the app came back to it).
    func cameraAppeared() async {
        cameraSessionShots = []
        if cameraAccess == .notAsked, !camera.isMock {
            cameraAccess = await CameraAccess.request()
        } else {
            cameraAccess = CameraAccess.current
        }
        if camera.isMock || cameraAccess == .granted { camera.start() }
    }

    func cameraDisappeared() {
        camera.stop()
    }

    func finishIntro() {
        introSeen = true
        QALog.write("intro done")
    }

    func resignedActive() {
        camera.stop()
        ticker?.invalidate()
        ticker = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        now = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    /// Drop tracked shots the user already deleted in Photos, so counts stay honest.
    private func reconcile() {
        guard library.canUse, !ledger.shots.isEmpty else { return }
        let ids = ledger.shots.map(\.id)
        let alive = library.existing(ids)
        let gone = ids.filter { !alive.contains($0) }
        if !gone.isEmpty {
            update { $0.forget(gone) }
            QALog.write("reconcile: \(gone.count) gone from library")
        }
    }

    private func seedIfAsked() async {
        #if DEBUG
        guard QA.seedForeign, !seeded, library.access == .full else { return }
        seeded = true
        await library.seedForeignPhoto(albumName: albumName)
        #endif
    }

    // MARK: Actions

    /// Shutter. Asks for Photos access on the first shot (not at launch), then saves and tracks.
    func shoot(flash: Bool) async {
        if library.access == .notAsked {
            photoAccess = await library.requestAccess()
            await seedIfAsked()
        }
        photoAccess = library.access
        guard library.canUse else {
            photosOffAlert = true
            return
        }
        do {
            let data = try await camera.capture(flash: flash)
            let saved = try await library.save(data, albumName: albumName)
            let captured = Date()
            update { $0.track(id: saved.id, capturedAt: captured, lifetime: lifetime, timeScale: timeScale) }
            cameraSessionShots.append(saved.id)
            if camera.isMock, QA.log { QALog.write("camera: mock got \(PhotoInfo(data: data).map(\.description) ?? "unreadable")") }
            QALog.write("saved \(saved.id) album=\(saved.inAlbum ? albumName : "-") lifetime=\(lifetime.rawValue)")
            if lifetime == .never, saved.inAlbum {
                show("Saved to \(albumName)")
            }
        } catch {
            QALog.write("shoot failed: \(error)")
            show("Could not save that shot")
        }
    }

    /// One batched delete of every expired tracked shot: one system confirmation.
    func clearExpired() async {
        let ids = ledger.deletable(at: Date())
        guard !ids.isEmpty, !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            let gone = try await library.delete(ids)
            update { $0.forget(gone) }
            show(gone.count == 1 ? "Cleared 1 photo" : "Cleared \(gone.count) photos")
        } catch {
            QALog.write("clear cancelled: \(error)")
        }
    }

    /// Stop this shot expiring. It stays in Photos as an ordinary photo and leaves the app's list.
    func keep(_ shot: Shot) {
        update { $0.forget([shot.id]) }
        show("Kept. It stays in Photos.")
        QALog.write("kept \(shot.id)")
    }

    /// Delete one shot now (iOS asks to confirm). Returns true if it was deleted.
    func deleteNow(_ shot: Shot) async -> Bool {
        guard ledger.contains(shot.id) else { return false }
        do {
            let gone = try await library.delete([shot.id])
            update { $0.forget(gone) }
            return true
        } catch {
            return false
        }
    }

    func requestPhotoAccess() async {
        photoAccess = await library.requestAccess()
    }

    func refreshAccess() {
        photoAccess = library.access
        cameraAccess = CameraAccess.current
    }

    func show(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    private func update(_ change: (inout Ledger) -> Void) {
        var copy = ledger
        change(&copy)
        ledger = copy
        file.save(copy)
    }
}
