import SwiftUI
import UIKit

/// App state: settings, the ledger of shots, and the actions the screens call.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var ledger: Ledger
    /// Shots whose shutter was pressed but whose file is not written yet. They show at once (grid, counter)
    /// and move into the ledger when the file is on disk; a failed save removes them again.
    @Published private(set) var pending: [Shot] = []
    /// Small pictures of brand-new shots (the mock camera's frame, or the photo's own preview), shown until
    /// the real thumbnail is in memory.
    @Published private(set) var instant: [String: UIImage] = [:]
    @Published private(set) var now = Date()
    @Published var lifetime: Lifetime { didSet { defaults.set(lifetime.rawValue, forKey: Keys.lifetime) } }
    /// The one-screen intro has been seen (it shows once, then from Settings > How it works).
    @Published private(set) var introSeen: Bool { didSet { defaults.set(introSeen, forKey: Keys.introSeen) } }
    /// Settings: skip the home screen and open on the camera. Off by default.
    @Published var openToCamera: Bool { didSet { defaults.set(openToCamera, forKey: Keys.openToCamera) } }
    /// The full screen camera is showing.
    @Published var cameraOpen = false
    /// Shots taken since the camera last opened, newest last, for the camera's counter and thumbnail.
    @Published private(set) var cameraSessionShots: [String] = []
    @Published private(set) var cameraAccess: CameraAccess
    @Published var toast: String?
    /// Save to Photos was refused: offer Settings.
    @Published var photosOffAlert = false

    let store: ShotStore
    let camera: Camera
    let timeScale = QA.timeScale
    private let file: LedgerFile
    private let defaults: UserDefaults
    /// False only while the ledger file exists but cannot be read yet. Nothing is saved or deleted then.
    private var ledgerLoaded: Bool
    private var cleanedUp = false
    private var ticker: Timer?
    private var toastTask: Task<Void, Never>?

    private enum Keys {
        static let lifetime = "lifetime"
        static let introSeen = "introSeen"
        static let openToCamera = "openToCamera"
        /// From the Photos-album version; removed on launch.
        static let oldAlbum = "albumName"
    }

    init(file: LedgerFile = .standard, store: ShotStore = .standard, defaults: UserDefaults = .standard,
         camera: Camera? = nil) {
        if QA.reset {
            file.reset()
            store.deleteAll()
            QALog.reset()
            defaults.removeObject(forKey: Keys.lifetime)
            defaults.removeObject(forKey: Keys.introSeen)
            defaults.removeObject(forKey: Keys.openToCamera)
        }
        defaults.removeObject(forKey: Keys.oldAlbum)
        self.file = file
        self.store = store
        self.defaults = defaults
        let loaded = file.load()
        ledger = loaded ?? Ledger()
        ledgerLoaded = loaded != nil
        lifetime = QA.lifetime ?? defaults.string(forKey: Keys.lifetime).flatMap(Lifetime.init(rawValue:)) ?? .default
        introSeen = defaults.bool(forKey: Keys.introSeen)
        openToCamera = defaults.bool(forKey: Keys.openToCamera)
        cameraAccess = CameraAccess.current
        self.camera = camera ?? (QA.mockCamera ? MockCamera() : RealCamera())
        cameraOpen = introSeen && openToCamera
        QALog.write("launch mock=\(self.camera.isMock) scale=\(timeScale) tracked=\(ledger.shots.count)")
    }

    // MARK: Derived

    /// Every shot, saved or still saving, newest first.
    var recent: [Shot] { (pending + ledger.shots).sorted { $0.capturedAt > $1.capturedAt } }
    var shotCount: Int { pending.count + ledger.shots.count }
    func remaining(_ shot: Shot) -> TimeInterval? { shot.remaining(at: now) }
    func isPending(_ shot: Shot) -> Bool { pending.contains { $0.id == shot.id } }
    var summary: String? {
        let next = recent.compactMap(\.expiresAt).filter { $0 > now }.min()
        return Ledger.summary(count: shotCount, next: next, now: now)
    }
    /// What a thumbnail can show right now, without waiting: the real thumbnail if it is in memory, else
    /// the instant picture from the shutter.
    func quickImage(_ id: String) -> UIImage? { store.cachedThumbnail(id) ?? instant[id] }
    func fileURL(_ shot: Shot) -> URL? { shot.file.isEmpty ? nil : store.url(for: shot.file) }

    // MARK: Lifecycle

    /// The app came to the front: delete what has expired, then keep checking every second.
    /// Camera access is asked when the camera first opens. With access already granted, the session is
    /// configured in the background so the camera opens quickly; it only runs while the camera is showing.
    func becameActive() {
        if !ledgerLoaded, let loaded = file.load() {
            ledger = loaded
            ledgerLoaded = true
        }
        cameraAccess = CameraAccess.current
        if cameraOpen, camera.isMock || cameraAccess == .granted {
            camera.start()   // back from the background with the camera showing
        } else if cameraAccess == .granted {
            camera.prepare()
        }
        cleanUpOnce()
        sweep()
        startTicker()
    }

    /// Once per launch, before any shot can be taken: forget shots whose file is gone, and delete files the
    /// ledger does not name (a save cut short by the app being killed).
    func cleanUpOnce() {
        guard ledgerLoaded, !cleanedUp else { return }
        cleanedUp = true
        let missing = ledger.shots.filter { !store.exists($0.file) }.map(\.id)
        if !missing.isEmpty { update { $0.forget(missing) } }
        let stray = store.deleteFiles(notIn: ledger.files)
        try? store.prepareFolder()
        QALog.write("cleanup: \(ledger.shots.count) shots, \(missing.count) missing files, \(stray) stray files")
    }

    /// Deletes every expired shot, file and ledger entry, with no prompt.
    func sweep(at date: Date = Date()) {
        guard ledgerLoaded else { return }
        var copy = ledger
        let gone = copy.removeExpired(at: date)
        guard !gone.isEmpty else { return }
        commit(copy)
        removeFiles(of: gone)
        QALog.write("expired \(gone.count): \(gone.map(\.id).joined(separator: " "))")
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

    /// The shutter works: the mock camera, or a real one the user allowed.
    var canShoot: Bool { camera.isMock || cameraAccess == .granted }

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
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.sweep(at: self.now)
            }
        }
    }

    // MARK: Actions

    /// Shutter. The shot shows straight away (counter, thumbnail, grid), before the photo is processed or
    /// written; it moves into the ledger once its file is on disk. Taps never wait for earlier shots.
    func shoot(flash: Bool) async {
        guard canShoot else { return }
        let id = UUID().uuidString
        let captured = Date().addingTimeInterval(-QA.demoAge(shot: cameraSessionShots.count + 1))
        let shot = Shot(id: id, file: "", capturedAt: captured, lifetime: lifetime, timeScale: timeScale)
        if let quick = camera.instantPreview() { instant[id] = quick }
        pending.append(shot)
        cameraSessionShots.append(id)
        do {
            let photo = try await camera.capture(flash: flash)
            if instant[id] == nil, let preview = photo.preview { instant[id] = preview }
            guard ledgerLoaded else { throw CameraError.notReady }
            let name = try await store.write(photo.data, id: id, capturedAt: captured)
            var saved = shot
            saved.file = name
            pending.removeAll { $0.id == id }
            update { $0.add(saved) }
            // The real thumbnail is in memory now, so the stand-in can go without a blank frame.
            if store.cachedThumbnail(id) != nil { instant[id] = nil }
            if camera.isMock, QA.log { QALog.write("camera: mock got \(PhotoInfo(data: photo.data).map(\.description) ?? "unreadable")") }
            QALog.write("saved \(id) file=\(name) lifetime=\(lifetime.rawValue)")
        } catch {
            pending.removeAll { $0.id == id }
            cameraSessionShots.removeAll { $0 == id }
            instant[id] = nil
            QALog.write("shoot failed: \(error)")
            show("Could not save that shot")
        }
    }

    /// Delete one shot now.
    func delete(_ shot: Shot) {
        guard ledgerLoaded, ledger.contains(shot.id) else { return }
        update { $0.forget([shot.id]) }
        removeFiles(of: [shot])
        QALog.write("deleted \(shot.id)")
    }

    /// Delete every shot now (Settings).
    func deleteAll() {
        guard ledgerLoaded else { return }
        let count = ledger.shots.count
        commit(Ledger())
        store.deleteAll()
        try? store.prepareFolder()
        instant = instant.filter { id, _ in pending.contains { $0.id == id } }
        QALog.write("deleted all \(count)")
    }

    /// Save to Photos: asks for add-only access the first time, then adds a copy of the original file.
    func saveToPhotos(_ shot: Shot) async {
        guard let url = fileURL(shot) else { return }
        do {
            try await PhotoSaver.save(fileAt: url, takenAt: shot.capturedAt)
            show("Saved to Photos")
            QALog.write("saved to photos \(shot.id)")
        } catch PhotoSaver.SaveError.noAccess {
            photosOffAlert = true
        } catch {
            QALog.write("save to photos failed: \(error)")
            show("Could not save to Photos")
        }
    }

    func refreshAccess() {
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

    private func removeFiles(of shots: [Shot]) {
        store.delete(shots.map(\.file))
        store.forgetThumbnails(shots.map(\.id))
        for shot in shots { instant[shot.id] = nil }
    }

    private func update(_ change: (inout Ledger) -> Void) {
        var copy = ledger
        change(&copy)
        commit(copy)
    }

    private func commit(_ new: Ledger) {
        guard ledgerLoaded else { return }
        ledger = new
        file.save(new)
    }
}
