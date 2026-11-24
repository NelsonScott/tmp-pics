import XCTest

/// The end-to-end flow in the simulator, in steps so qa/e2e.sh can read the simulator's Photos database
/// between them:
///   test1: fresh start, intro, empty home, camera, Photos permission prompt, three mock shots, Done,
///          home grid, Keep one, settings, How it works.
///   test2: wait on the home screen for the other two to expire, Clear, confirm the system delete prompt.
///   test3: "Open straight to camera" on, relaunch lands in the camera, Done goes home; then off again.
/// Screenshots go to /tmp/tmp-sim-qa/<TMP_SHOT_TAG>-<name>.png on the Mac.
final class FlowUITests: XCTestCase {
    /// 24 hours pass in 60 seconds.
    static let timeScale = "1440"
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TMP_MOCK_CAMERA"] = "1"
        app.launchEnvironment["TMP_TIME_SCALE"] = Self.timeScale
        app.launchEnvironment["TMP_QA_LOG"] = "1"
    }

    func test1_CaptureAndKeep() throws {
        app.launchEnvironment["TMP_RESET"] = "1"
        app.launchEnvironment["TMP_QA_SEED_FOREIGN"] = "1"
        app.launch()

        // First run: the intro, once.
        let start = app.buttons["intro-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        sleep(1)
        shot("01-intro")
        start.tap()

        let openCamera = app.buttons["open-camera"]
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        XCTAssertTrue(element("home-empty").exists)
        XCTAssertTrue(element("home-empty").label.contains("expire after 24 hours"), "fresh install default: 24 hours")
        XCTAssertGreaterThanOrEqual(openCamera.frame.height, 88, "the camera button is a big target")
        sleep(1)
        shot("02-home-empty")

        openCamera.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["last-shot"].exists, "no shots yet this visit")
        sleep(1)
        shot("03-camera")

        shutter.tap()
        // First shot asks for Photos access (unless already granted).
        if let allow = systemButton(["Allow Full Access", "Allow Access to All Photos", "Allow"], timeout: 6) {
            sleep(1)
            shot("04-photos-permission")
            allow.tap()
        }
        waitForSaved(1)
        shutter.tap()
        waitForSaved(2)
        shutter.tap()
        waitForSaved(3)
        XCTAssertTrue(shutter.exists, "the camera stays open after each shot")
        sleep(1)
        shot("05-camera-three-shots")

        app.buttons["camera-done"].tap()
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        waitForShots(3)
        XCTAssertTrue(element("summary").label.hasPrefix("3 photos. Next one expires in"), element("summary").label)
        sleep(1)
        shot("06-home-three-shots")

        // Open the oldest and keep it.
        app.buttons.matching(identifier: "shot").element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["keep"].waitForExistence(timeout: 5))
        sleep(1)
        shot("07-viewer")
        app.buttons["keep"].tap()
        XCTAssertTrue(app.buttons["viewer-done"].waitForExistence(timeout: 3))
        app.buttons["viewer-done"].tap()
        waitForShots(2)
        sleep(1)
        shot("08-after-keep")

        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        sleep(1)
        shot("09-settings")
        let howItWorks = app.buttons["how-it-works"]
        scrollTo(howItWorks)
        shot("10-settings-bottom")
        howItWorks.tap()
        let again = app.buttons["intro-start"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.label, "Done")
        sleep(1)
        shot("11-how-it-works")
        again.tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()
    }

    func test2_ExpireAndClear() throws {
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10), "home, not the intro, from now on")
        XCTAssertEqual(app.buttons.matching(identifier: "shot").count, 2, "the two unkept shots from test1")
        let clear = app.buttons["clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 120), "shots should expire within the fast clock")
        // The banner shows as soon as the first one expires; the second follows a second or so later.
        let summary = element("summary")
        let allExpired = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in summary.label == "2 photos, all expired." }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [allExpired], timeout: 10), .completed, summary.label)
        XCTAssertTrue(app.staticTexts["2 expired photos"].exists)
        sleep(1)
        shot("12-home-expired")

        clear.tap()
        guard let delete = systemButton(["Delete"], timeout: 10) else {
            shot("13-no-delete-prompt")
            XCTFail("no system delete prompt")
            return
        }
        sleep(1)
        shot("13-delete-prompt")
        delete.tap()
        XCTAssertTrue(element("home-empty").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["clear"].exists)
        sleep(1)
        shot("14-cleared")
    }

    func test3_StraightToCamera() throws {
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10))
        setOpenToCamera(true)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 10), "opens on the camera")
        sleep(1)
        shot("15-straight-to-camera")
        app.buttons["camera-done"].tap()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 5), "Done still goes home")

        setOpenToCamera(false)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10), "back to home first")
        XCTAssertFalse(app.buttons["shutter"].exists)
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The camera's last-shot thumbnail carries the count of shots saved this visit as its value.
    private func waitForSaved(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let thumb = app.buttons["last-shot"]
        let predicate = NSPredicate { _, _ in thumb.exists && (thumb.value as? String) == "\(n)" }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed, "expected \(n) saved this visit", file: file, line: line)
    }

    private func scrollTo(_ element: XCUIElement) {
        var tries = 0
        // Clear of the home indicator too, so a tap lands (matters at the largest text sizes).
        let bottom = app.frame.maxY - 100
        while !(element.exists && element.isHittable && element.frame.maxY < bottom), tries < 8 {
            app.swipeUp()
            tries += 1
        }
        sleep(1)
    }

    private func setOpenToCamera(_ on: Bool) {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        let toggle = app.switches["open-to-camera"]
        scrollTo(toggle)
        if (toggle.value as? String == "1") != on {
            toggle.switches.firstMatch.tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0")
        app.buttons["settings-done"].tap()
    }

    private func waitForShots(_ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in self.app.buttons.matching(identifier: "shot").count == n }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 10), .completed, "expected \(n) shots on the home screen", file: file, line: line)
    }

    /// A button in a system alert, wherever iOS presents it (SpringBoard or the app's own process).
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
        let tag = ProcessInfo.processInfo.environment["TMP_SHOT_TAG"] ?? "run"
        let dir = URL(fileURLWithPath: "/tmp/tmp-sim-qa")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("\(tag)-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
