import AVFoundation
import UIKit
import XCTest
@testable import TmpCamera

/// A camera whose captures finish only when the test says so, so the moments between the shutter and the
/// saved file can be checked.
@MainActor
final class FakeCamera: Camera {
    let isMock = true
    var position: AVCaptureDevice.Position = .back
    let hasFlash = false
    let maxZoom: CGFloat = 1
    var waiting: [CheckedContinuation<CapturedPhoto, Error>] = []
    var preview: UIImage? = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { ctx in
        UIColor.orange.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
    }

    func prepare() {}
    func start() {}
    func stop() {}
    func flip() {}
    func setZoom(_ factor: CGFloat) {}
    func instantPreview() -> UIImage? { preview }
    func capture(flash: Bool) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    /// Finishes the oldest waiting capture.
    func finish(_ result: Result<CapturedPhoto, Error> = .success(CapturedPhoto(data: TestImages.jpeg(), preview: nil))) {
        waiting.removeFirst().resume(with: result)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    var root: URL!
    var defaults: UserDefaults!
    var suite: String!
    var camera: FakeCamera!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "tmp-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        camera = FakeCamera()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    var ledgerFile: LedgerFile { LedgerFile(url: root.appendingPathComponent("ledger.json")) }
    var store: ShotStore { ShotStore(dir: root.appendingPathComponent("Shots")) }

    private func makeModel(store: ShotStore? = nil) -> AppModel {
        AppModel(file: ledgerFile, store: store ?? self.store, defaults: defaults, camera: camera)
    }

    /// Lets queued main-actor tasks run until `condition` holds.
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    func testFreshInstallDefaults() {
        defaults.set("Tmp", forKey: "albumName")   // left by the Photos-album version
        let model = makeModel()
        XCTAssertEqual(model.lifetime, .oneDay, "a fresh install deletes shots after 24 hours")
        XCTAssertEqual(model.lifetime.label, "24 hours")
        XCTAssertFalse(model.introSeen, "the intro shows on first launch")
        XCTAssertFalse(model.openToCamera, "Open straight to camera is off by default")
        XCTAssertFalse(model.cameraOpen, "first launch is not the camera")
        XCTAssertTrue(model.ledger.shots.isEmpty)
        XCTAssertNil(defaults.object(forKey: "albumName"), "the old album setting is gone")
    }

    /// The shot is in the grid and the counter the moment the shutter is pressed, with a picture, before
    /// the camera has delivered the photo or anything is on disk.
    func testShotShowsBeforeItIsSaved() async throws {
        let model = makeModel()
        let shooting = Task { await model.shoot(flash: false) }
        await waitUntil { camera.waiting.count == 1 }
        XCTAssertEqual(model.recent.count, 1)
        XCTAssertEqual(model.cameraSessionShots.count, 1, "the counter bumps at once")
        let id = try XCTUnwrap(model.recent.first?.id)
        XCTAssertTrue(model.isPending(model.recent[0]))
        XCTAssertNotNil(model.quickImage(id), "the instant picture is there for the thumbnail")
        XCTAssertTrue(model.ledger.shots.isEmpty, "not in the saved ledger yet")
        XCTAssertTrue(store.allFiles().isEmpty, "nothing written yet")
        XCTAssertEqual(model.summary, "1 photo. It expires in 1 day.")

        camera.finish()
        await shooting.value
        XCTAssertEqual(model.ledger.shots.map(\.id), [id])
        XCTAssertTrue(model.pending.isEmpty)
        let saved = model.ledger.shots[0]
        XCTAssertTrue(store.exists(saved.file))
        XCTAssertEqual(ledgerFile.load()?.shots.map(\.id), [id], "saved to the ledger file")
        XCTAssertNotNil(model.quickImage(id), "the real thumbnail took over")
        XCTAssertNil(model.instant[id], "the stand-in is dropped once the real thumbnail is in memory")
    }

    /// Quick taps: every shot shows at once, none waits for the one before it.
    func testRapidShotsEachShowAtOnce() async {
        let model = makeModel()
        let first = Task { await model.shoot(flash: false) }
        let second = Task { await model.shoot(flash: false) }
        let third = Task { await model.shoot(flash: false) }
        await waitUntil { camera.waiting.count == 3 }
        XCTAssertEqual(model.recent.count, 3)
        XCTAssertEqual(model.cameraSessionShots.count, 3)
        camera.finish()
        camera.finish()
        camera.finish()
        _ = await (first.value, second.value, third.value)
        XCTAssertEqual(model.ledger.shots.count, 3)
        XCTAssertEqual(Set(model.ledger.shots.map(\.file)).count, 3, "each shot has its own file")
        XCTAssertEqual(store.allFiles().count, 3)
    }

    /// The shot is withdrawn again when the file cannot be written.
    func testFailedWriteRemovesTheShot() async throws {
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let model = makeModel(store: ShotStore(dir: blocker.appendingPathComponent("Shots")))
        let shooting = Task { await model.shoot(flash: false) }
        await waitUntil { camera.waiting.count == 1 }
        XCTAssertEqual(model.recent.count, 1)
        camera.finish()
        await shooting.value
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertTrue(model.cameraSessionShots.isEmpty, "the counter goes back down")
        XCTAssertTrue(model.instant.isEmpty)
        XCTAssertEqual(model.toast, "Could not save that shot")
    }

    func testFailedCaptureRemovesTheShot() async {
        let model = makeModel()
        let shooting = Task { await model.shoot(flash: false) }
        await waitUntil { camera.waiting.count == 1 }
        camera.finish(.failure(CameraError.noData))
        await shooting.value
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertEqual(model.toast, "Could not save that shot")
    }

    private func takeShot(_ model: AppModel) async {
        let shooting = Task { await model.shoot(flash: false) }
        await waitUntil { camera.waiting.count == 1 }
        camera.finish()
        await shooting.value
    }

    func testExpiredShotsDeleteThemselves() async {
        let model = makeModel()
        model.lifetime = .oneHour
        await takeShot(model)
        model.lifetime = .never
        await takeShot(model)
        XCTAssertEqual(store.allFiles().count, 2)
        let hourly = model.ledger.shots.first { $0.expiresAt != nil }!
        model.sweep(at: Date().addingTimeInterval(1800))
        XCTAssertEqual(model.ledger.shots.count, 2, "not yet")
        model.sweep(at: Date().addingTimeInterval(3601))
        XCTAssertEqual(model.ledger.shots.count, 1, "the hourly shot is gone, with no prompt")
        XCTAssertFalse(store.exists(hourly.file), "and so is its file")
        XCTAssertNil(model.quickImage(hourly.id))
        XCTAssertEqual(store.allFiles().count, 1)
        XCTAssertEqual(ledgerFile.load()?.shots.count, 1)
        model.sweep(at: Date().addingTimeInterval(100 * 86_400))
        XCTAssertEqual(model.ledger.shots.count, 1, "a Never shot stays")
    }

    func testChangingLifetimeAppliesToNewShotsOnly() async {
        let model = makeModel()
        model.lifetime = .oneHour
        await takeShot(model)
        model.lifetime = .sevenDays
        model.sweep(at: Date().addingTimeInterval(3601))
        XCTAssertTrue(model.ledger.shots.isEmpty, "the shot keeps the lifetime it was taken with")
    }

    func testDeleteOneAndDeleteAll() async {
        let model = makeModel()
        await takeShot(model)
        await takeShot(model)
        await takeShot(model)
        let first = model.ledger.shots[0]
        model.delete(first)
        XCTAssertEqual(model.ledger.shots.count, 2)
        XCTAssertFalse(store.exists(first.file))
        model.deleteAll()
        XCTAssertTrue(model.ledger.shots.isEmpty)
        XCTAssertTrue(store.allFiles().isEmpty)
        XCTAssertEqual(ledgerFile.load(), Ledger())
    }

    /// A dev phone with the Photos-album version's ledger: it loads empty and nothing crashes.
    func testOldLedgerIsReset() throws {
        let old = #"{"shots":[{"id":"9F2C1A7E-1111-2222-3333-444455556666/L0/001","capturedAt":800000000,"expiresAt":800086400}]}"#
        try Data(old.utf8).write(to: ledgerFile.url)
        let model = makeModel()
        XCTAssertTrue(model.ledger.shots.isEmpty)
        model.cleanUpOnce()
        model.sweep()
        XCTAssertTrue(model.recent.isEmpty)
    }

    /// At launch: shots whose file is gone are forgotten, files the ledger does not name are deleted.
    func testLaunchCleanup() async throws {
        let first = makeModel()
        await takeShot(first)
        await takeShot(first)
        let lost = first.ledger.shots[0]
        try FileManager.default.removeItem(at: store.url(for: lost.file))
        try Data("cut short".utf8).write(to: store.url(for: "Tmp 2026-01-01 at 00.00.00.heic"))

        let model = makeModel()
        model.cleanUpOnce()
        XCTAssertEqual(model.ledger.shots.count, 1)
        XCTAssertFalse(model.ledger.contains(lost.id))
        XCTAssertEqual(store.allFiles(), [model.ledger.shots[0].file])
    }

    /// If the ledger cannot be read (it exists, but not readable yet), no photo file is touched.
    func testUnreadableLedgerTouchesNothing() async throws {
        let first = makeModel()
        await takeShot(first)
        try FileManager.default.removeItem(at: ledgerFile.url)
        try FileManager.default.createDirectory(at: ledgerFile.url, withIntermediateDirectories: true)
        let model = makeModel()
        model.cleanUpOnce()
        model.sweep(at: Date().addingTimeInterval(1000 * 86_400))
        model.deleteAll()
        XCTAssertEqual(store.allFiles().count, 1, "the photo is still there")
    }
}
