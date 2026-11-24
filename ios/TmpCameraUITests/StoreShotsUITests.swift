import XCTest

/// App Store screenshots, with stand-in photos instead of the numbered mock frames (TMP_DEMO_PHOTOS).
/// Skipped unless TMP_STORE_SHOTS=1; store/tools/shots.sh runs it. Screenshots go to
/// /tmp/tmp-sim-qa/store-<name>.png on the Mac.
///
/// The clock runs at normal speed. TMP_DEMO_AGES backdates each shot's capture time, so the grid shows a
/// spread of real times left (23h down to 4h).
final class StoreShotsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["TMP_STORE_SHOTS"] == "1" else {
            throw XCTSkip("App Store screenshots only: TMP_STORE_SHOTS=1 (store/tools/shots.sh)")
        }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TMP_MOCK_CAMERA"] = "1"
        app.launchEnvironment["TMP_DEMO_PHOTOS"] = "1"
        app.launchEnvironment["TMP_RESET"] = "1"
    }

    /// Intro, camera, home, viewer, share sheet, settings.
    func test1_Main() throws {
        app.launchEnvironment["TMP_DEMO_AGES"] = "20,16,12.5,8,3.2,0.4"
        app.launch()

        let start = app.buttons["intro-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        sleep(1)
        shot("intro")
        start.tap()

        takeSix { n in
            if n == 2 {
                sleep(1)
                self.shot("camera")   // two saved, the router sticker in the viewfinder
            }
        }
        sleep(1)
        shot("home")

        // Newest first: the receipt (shot 2) is the fifth tile.
        app.buttons.matching(identifier: "shot").element(boundBy: 4).tap()
        XCTAssertTrue(app.buttons["save-to-photos"].waitForExistence(timeout: 5))
        sleep(2)
        shot("viewer")

        app.buttons["share"].tap()
        let copy = app.buttons["Copy"]
        let sheet = app.otherElements["ActivityListView"]
        let end = Date().addingTimeInterval(8)
        while !(copy.exists || sheet.exists), Date() < end { usleep(250_000) }
        XCTAssertTrue(copy.exists || sheet.exists, "the share sheet opens")
        sleep(2)
        shot("share")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(app.buttons["viewer-done"].waitForExistence(timeout: 5))
        app.buttons["viewer-done"].tap()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 5))

        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Testing"].exists, "no Testing section in store shots")
        sleep(1)
        shot("settings")
        app.buttons["settings-done"].tap()
    }

    /// Opens the camera, takes six shots, goes home.
    private func takeSix(after: (Int) -> Void) {
        let openCamera = app.buttons["open-camera"]
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        openCamera.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Test mode"].exists, "no test pill in store shots")
        for n in 1...6 {
            shutter.tap()
            waitForSaved(n)
            after(n)
        }
        app.buttons["camera-done"].tap()
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        waitForShots(6)
    }

    // MARK: Helpers (as in FlowUITests)

    private func waitForSaved(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let thumb = app.buttons["last-shot"]
        let predicate = NSPredicate { _, _ in thumb.exists && (thumb.value as? String) == "\(n)" }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed, "expected \(n) saved this visit", file: file, line: line)
    }

    private func waitForShots(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in self.app.buttons.matching(identifier: "shot").count == n }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed, "expected \(n) shots on the home screen", file: file, line: line)
    }

    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: "/tmp/tmp-sim-qa")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("store-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
