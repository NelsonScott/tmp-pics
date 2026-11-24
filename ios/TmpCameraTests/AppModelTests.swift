import XCTest
@testable import TmpCamera

/// What a fresh install starts with: nothing in UserDefaults, no ledger file.
@MainActor
final class AppModelTests: XCTestCase {
    func testFreshInstallDefaults() throws {
        let suite = "tmp-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
        let model = AppModel(file: LedgerFile(url: dir.appendingPathComponent("ledger.json")), defaults: defaults)
        XCTAssertEqual(model.lifetime, .oneDay, "a fresh install expires shots after 24 hours")
        XCTAssertEqual(model.lifetime.label, "24 hours")
        XCTAssertEqual(model.albumName, "Tmp")
        XCTAssertFalse(model.introSeen, "the intro shows on first launch")
        XCTAssertFalse(model.openToCamera, "Open straight to camera is off by default")
        XCTAssertFalse(model.cameraOpen, "first launch is not the camera")
        XCTAssertTrue(model.ledger.shots.isEmpty)
    }
}
