import XCTest

/// App Store screenshots, with stand-in photos instead of the numbered mock frames (TMP_DEMO_PHOTOS).
/// Skipped unless TMP_STORE_SHOTS=1; store/tools/shots.sh runs it. Screenshots go to
/// /tmp/tmp-sim-qa/store-<name>.png on the Mac.
///
/// The clock runs at normal speed. TMP_DEMO_AGES backdates each shot's capture time, so the grid shows a
/// spread of real times left (23h down to 4h), and in test2 the two oldest are already past 24 hours.
final class StoreShotsUITests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
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

    /// Intro, camera, home, viewer, settings.
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
        XCTAssertTrue(app.buttons["keep"].waitForExistence(timeout: 5))
        sleep(2)
        shot("viewer")
        app.buttons["viewer-done"].tap()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 5))

        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Testing"].exists, "no Testing section in store shots")
        sleep(1)
        shot("settings")
        app.buttons["settings-done"].tap()
    }

    /// Two shots past 24 hours: the expired banner, Clear, the system delete prompt.
    func test2_Expired() throws {
        app.launchEnvironment["TMP_DEMO_AGES"] = "25,24.5,14,9,4,1"
        app.launch()
        let start = app.buttons["intro-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        takeSix { _ in }
        XCTAssertTrue(app.staticTexts["2 expired photos"].waitForExistence(timeout: 5))
        sleep(1)
        shot("expired")

        app.buttons["clear"].tap()
        guard let delete = systemButton(["Delete"], timeout: 10) else {
            XCTFail("no system delete prompt")
            return
        }
        sleep(1)
        shot("delete-prompt")
        delete.tap()
        waitForShots(4)
    }

    /// Opens the camera, takes six shots (granting Photos access on the first), goes home.
    private func takeSix(after: (Int) -> Void) {
        let openCamera = app.buttons["open-camera"]
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        openCamera.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Test mode"].exists, "no test pill in store shots")
        for n in 1...6 {
            shutter.tap()
            if n == 1, let allow = systemButton(["Allow Full Access", "Allow Access to All Photos", "Allow"], timeout: 4) {
                allow.tap()
            }
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

    private func systemButton(_ labels: [String], timeout: TimeInterval) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for source in [springboard, app!] {
                for label in labels {
                    let button = source.alerts.buttons[label]
                    if button.exists { return button }
                }
            }
            usleep(250_000)
        } while Date() < end
        return nil
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
