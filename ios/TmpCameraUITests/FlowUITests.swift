import XCTest

/// The end-to-end flow in the simulator, in steps so qa/e2e.sh can look at the app's Shots folder and the
/// simulator's Photos database between them:
///   test1: fresh start, intro, empty home, camera, three mock shots, Done, home grid, viewer: Share sheet,
///          Save to Photos (the add-only prompt), Delete one; settings, How it works.
///   test2: wait on the home screen; the other two expire and vanish by themselves, with no prompt.
///   test3: "Open straight to camera" on, relaunch lands in the camera, Done goes home; then off again.
///   test4: two shots, Settings > Delete all photos now, confirm, empty home.
///   test5: the real camera with camera access refused: the camera-off state, no working shutter.
/// Screenshots go to /tmp/tmp-sim-qa/<TMP_SHOT_TAG>-<name>.png on the Mac.
final class FlowUITests: XCTestCase {
    /// 24 hours pass in 2 minutes: long enough for test1 to finish with its shots still there.
    static let timeScale = "720"
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TMP_MOCK_CAMERA"] = "1"
        app.launchEnvironment["TMP_TIME_SCALE"] = Self.timeScale
        app.launchEnvironment["TMP_QA_LOG"] = "1"
    }

    func test1_CaptureShareSaveDelete() throws {
        app.launchEnvironment["TMP_RESET"] = "1"
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
        XCTAssertTrue(element("home-empty").label.contains("delete themselves after 24 hours"), "fresh install default: 24 hours")
        XCTAssertGreaterThanOrEqual(openCamera.frame.height, 88, "the camera button is a big target")
        sleep(1)
        shot("02-home-empty")

        openCamera.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["last-shot"].exists, "no shots yet this visit")
        sleep(1)
        shot("03-camera")

        // No Photos prompt: shots stay in the app.
        shutter.tap()
        waitForSaved(1)
        XCTAssertNil(systemButton(["Allow", "Allow Full Access"], timeout: 1), "taking a photo asks for nothing")
        shutter.tap()
        waitForSaved(2)
        shutter.tap()
        waitForSaved(3)
        XCTAssertTrue(shutter.exists, "the camera stays open after each shot")
        sleep(1)
        shot("04-camera-three-shots")

        app.buttons["camera-done"].tap()
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
        waitForShots(3)
        XCTAssertTrue(element("summary").label.hasPrefix("3 photos. Next one expires in"), element("summary").label)
        sleep(1)
        shot("05-home-three-shots")

        // Open the oldest.
        app.buttons.matching(identifier: "shot").element(boundBy: 2).tap()
        let save = app.buttons["save-to-photos"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        sleep(1)
        shot("06-viewer")

        // Share: the system share sheet with the original file.
        app.buttons["share"].tap()
        XCTAssertTrue(waitForShareSheet(), "the share sheet opens")
        sleep(1)
        shot("07-share-sheet")
        closeShareSheet()
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        // Save to Photos asks for add-only access, only now (unless it was allowed on an earlier run).
        save.tap()
        let saved = app.staticTexts["Saved to Photos"]
        let end = Date().addingTimeInterval(8)
        while !saved.exists, Date() < end {
            if let allow = systemButton(["Allow"], timeout: 0.3) {
                sleep(1)
                shot("08-save-permission")
                allow.tap()
            }
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Saved to Photos")
        shot("09-saved-to-photos")

        // Delete this one: a light confirm, then it is gone.
        app.buttons["delete"].tap()
        let confirm = app.buttons["Delete Photo"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["viewer-done"].waitForExistence(timeout: 3), "the viewer moves on to the next shot")
        app.buttons["viewer-done"].tap()
        waitForShots(2)
        sleep(1)
        shot("10-after-delete")

        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        sleep(1)
        shot("11-settings")
        let howItWorks = app.buttons["how-it-works"]
        scrollTo(howItWorks)
        shot("12-settings-bottom")
        howItWorks.tap()
        let again = app.buttons["intro-start"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.label, "Done")
        sleep(1)
        shot("13-how-it-works")
        again.tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()
    }

    func test2_ExpireByThemselves() throws {
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10), "home, not the intro, from now on")
        XCTAssertEqual(app.buttons.matching(identifier: "shot").count, 2, "the two shots left from test1")
        shot("14-home-counting-down")
        // 24 hours last 2 minutes. They go by themselves: no banner, no prompt, nothing to tap.
        XCTAssertTrue(element("home-empty").waitForExistence(timeout: 180), "shots should vanish within the fast clock")
        XCTAssertEqual(app.buttons.matching(identifier: "shot").count, 0)
        XCTAssertEqual(springboard.alerts.count + app.alerts.count, 0, "no prompt of any kind")
        sleep(1)
        shot("15-expired-gone")
    }

    func test3_StraightToCamera() throws {
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10))
        setOpenToCamera(true)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 10), "opens on the camera")
        sleep(1)
        shot("16-straight-to-camera")
        app.buttons["camera-done"].tap()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 5), "Done still goes home")

        setOpenToCamera(false)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-camera"].waitForExistence(timeout: 10), "back to home first")
        XCTAssertFalse(app.buttons["shutter"].exists)
    }

    func test4_DeleteAll() throws {
        app.launch()
        let openCamera = app.buttons["open-camera"]
        XCTAssertTrue(openCamera.waitForExistence(timeout: 10))
        let before = app.buttons.matching(identifier: "shot").count
        openCamera.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        waitForSaved(1)
        shutter.tap()
        waitForSaved(2)
        app.buttons["camera-done"].tap()
        waitForShots(before + 2)

        app.buttons["settings"].tap()
        let deleteAll = app.buttons["delete-all"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 5))
        scrollTo(deleteAll)
        deleteAll.tap()
        let confirm = app.buttons["Delete All"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        sleep(1)
        shot("17-delete-all")
        confirm.tap()
        XCTAssertFalse(deleteAll.isEnabled, "nothing left to delete")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(element("home-empty").waitForExistence(timeout: 5))
    }

    func test5_CameraAccessOff() throws {
        app.launchEnvironment["TMP_MOCK_CAMERA"] = "0"
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        let openCamera = app.buttons["open-camera"]
        XCTAssertTrue(openCamera.waitForExistence(timeout: 10))
        openCamera.tap()
        if let refuse = systemButton(["Don’t Allow", "Don't Allow"], timeout: 8) {
            refuse.tap()
        }
        XCTAssertTrue(element("camera-off").waitForExistence(timeout: 5), "the camera-off state shows")
        XCTAssertTrue(app.buttons["camera-settings"].exists, "with a way to Settings")
        XCTAssertFalse(app.buttons["shutter"].isEnabled, "the shutter does nothing")
        sleep(1)
        shot("18-camera-off")
        app.buttons["camera-done"].tap()
        XCTAssertTrue(openCamera.waitForExistence(timeout: 5))
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

    /// The system share sheet (its own process view inside the app's window).
    private func waitForShareSheet() -> Bool {
        let sheet = app.otherElements["ActivityListView"]
        let copy = app.buttons["Copy"]
        let end = Date().addingTimeInterval(8)
        repeat {
            if sheet.exists || copy.exists { return true }
            usleep(250_000)
        } while Date() < end
        return false
    }

    private func closeShareSheet() {
        for label in ["Close", "close"] where app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        app.swipeDown(velocity: .fast)
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
