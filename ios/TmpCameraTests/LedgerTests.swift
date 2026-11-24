import XCTest
@testable import TmpCamera

final class LedgerTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTrackUsesLifetime() {
        var ledger = Ledger()
        let shot = ledger.track(id: "A/L0/001", capturedAt: t0, lifetime: .oneDay)
        XCTAssertEqual(shot?.expiresAt, t0.addingTimeInterval(86_400))
        XCTAssertEqual(ledger.shots.count, 1)
    }

    func testEveryLifetimeChoice() {
        let expected: [Lifetime: TimeInterval?] = [.oneHour: 3600, .oneDay: 86_400, .threeDays: 259_200, .sevenDays: 604_800, .never: nil]
        for (lifetime, seconds) in expected { XCTAssertEqual(lifetime.seconds, seconds, lifetime.label) }
        XCTAssertEqual(Lifetime.default, .oneDay)
    }

    func testNeverIsNotTracked() {
        var ledger = Ledger()
        XCTAssertNil(ledger.track(id: "A", capturedAt: t0, lifetime: .never))
        XCTAssertTrue(ledger.shots.isEmpty)
    }

    func testDuplicateIdIgnored() {
        var ledger = Ledger()
        ledger.track(id: "A", capturedAt: t0, lifetime: .oneHour)
        XCTAssertNil(ledger.track(id: "A", capturedAt: t0.addingTimeInterval(5), lifetime: .oneDay))
        XCTAssertEqual(ledger.shots.count, 1)
    }

    func testExpiryBoundary() {
        var ledger = Ledger()
        ledger.track(id: "A", capturedAt: t0, lifetime: .oneHour)
        XCTAssertTrue(ledger.expired(at: t0.addingTimeInterval(3599)).isEmpty)
        XCTAssertEqual(ledger.expired(at: t0.addingTimeInterval(3600)).map(\.id), ["A"])
    }

    func testFastForwardScalesLifetime() {
        var ledger = Ledger()
        let shot = ledger.track(id: "A", capturedAt: t0, lifetime: .oneDay, timeScale: 3600)
        XCTAssertEqual(shot?.expiresAt, t0.addingTimeInterval(24))
        var normal = Ledger()
        XCTAssertEqual(normal.track(id: "B", capturedAt: t0, lifetime: .oneHour, timeScale: 0)?.expiresAt,
                       t0.addingTimeInterval(3600), "a bad scale falls back to real time")
    }

    func testDeletableIsOnlyExpiredTrackedShots() {
        var ledger = Ledger()
        ledger.track(id: "old1", capturedAt: t0, lifetime: .oneHour)
        ledger.track(id: "old2", capturedAt: t0.addingTimeInterval(10), lifetime: .oneHour)
        ledger.track(id: "fresh", capturedAt: t0.addingTimeInterval(3000), lifetime: .oneHour)
        let now = t0.addingTimeInterval(3700)
        XCTAssertEqual(ledger.deletable(at: now), ["old1", "old2"])
        XCTAssertFalse(ledger.deletable(at: now).contains("someone-elses-photo"))
    }

    func testKeepAndForget() {
        var ledger = Ledger()
        ledger.track(id: "A", capturedAt: t0, lifetime: .oneHour)
        ledger.track(id: "B", capturedAt: t0, lifetime: .oneHour)
        ledger.forget(["A", "not-tracked"])
        XCTAssertEqual(ledger.shots.map(\.id), ["B"])
        XCTAssertFalse(ledger.contains("A"))
        XCTAssertEqual(ledger.deletable(at: t0.addingTimeInterval(99_999)), ["B"], "a kept shot is never deleted")
    }

    func testRecentIsNewestFirst() {
        var ledger = Ledger()
        ledger.track(id: "first", capturedAt: t0, lifetime: .oneDay)
        ledger.track(id: "second", capturedAt: t0.addingTimeInterval(60), lifetime: .oneDay)
        XCTAssertEqual(ledger.recent(at: t0).map(\.id), ["second", "first"])
    }

    func testNextExpiry() {
        var ledger = Ledger()
        ledger.track(id: "A", capturedAt: t0, lifetime: .oneHour)
        ledger.track(id: "B", capturedAt: t0, lifetime: .oneDay)
        XCTAssertEqual(ledger.nextExpiry(after: t0), t0.addingTimeInterval(3600))
        XCTAssertEqual(ledger.nextExpiry(after: t0.addingTimeInterval(4000)), t0.addingTimeInterval(86_400))
        XCTAssertNil(ledger.nextExpiry(after: t0.addingTimeInterval(90_000)))
    }

    func testLabels() {
        XCTAssertEqual(remainingLabel(0), "Expired")
        XCTAssertEqual(remainingLabel(30), "30s")
        XCTAssertEqual(remainingLabel(59.2), "1m")
        XCTAssertEqual(remainingLabel(45 * 60), "45m")
        XCTAssertEqual(remainingLabel(23 * 3600 + 1), "23h")
        XCTAssertEqual(remainingLabel(3 * 86_400), "3d")
        XCTAssertEqual(remainingPhrase(3600), "Expires in 1 hour")
        XCTAssertEqual(remainingPhrase(2 * 86_400), "Expires in 2 days")
        XCTAssertEqual(remainingPhrase(-1), "Expired")
    }

    func testSummaryLine() {
        var ledger = Ledger()
        XCTAssertNil(ledger.summary(at: t0), "nothing tracked: the empty state speaks instead")
        ledger.track(id: "A", capturedAt: t0, lifetime: .oneDay)
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(3600)), "1 photo. It expires in 23 hours.")
        ledger.track(id: "B", capturedAt: t0.addingTimeInterval(60), lifetime: .oneHour)
        ledger.track(id: "C", capturedAt: t0.addingTimeInterval(120), lifetime: .oneDay)
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(60)), "3 photos. Next one expires in 1 hour.")
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(3700)), "3 photos. Next one expires in 22 hours.",
                       "an expired shot does not count as next")
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(200_000)), "3 photos, all expired.")
        ledger.forget(["B", "C"])
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(200_000)), "1 photo, expired.")
    }

    func testDurationPhrase() {
        XCTAssertEqual(durationPhrase(1), "1 second")
        XCTAssertEqual(durationPhrase(0.2), "1 second")
        XCTAssertEqual(durationPhrase(120), "2 minutes")
        XCTAssertEqual(durationPhrase(5 * 3600 + 59 * 60), "5 hours")
        XCTAssertEqual(durationPhrase(86_400), "1 day")
    }

    func testFileRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = LedgerFile(url: dir.appendingPathComponent("ledger.json"))
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(file.load(), Ledger(), "missing file loads empty")
        var ledger = Ledger()
        ledger.track(id: "A/L0/001", capturedAt: t0, lifetime: .threeDays)
        file.save(ledger)
        XCTAssertEqual(file.load(), ledger)
        try Data("not json".utf8).write(to: file.url)
        XCTAssertEqual(file.load(), Ledger(), "a corrupt file never crashes; it loads empty")
        file.reset()
        XCTAssertEqual(file.load(), Ledger())
    }
}
