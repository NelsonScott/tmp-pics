import XCTest
@testable import TmpCamera

final class LedgerTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func shot(_ id: String, at offset: TimeInterval = 0, _ lifetime: Lifetime = .oneDay, scale: Double = 1) -> Shot {
        Shot(id: id, file: "\(id).jpg", capturedAt: t0.addingTimeInterval(offset), lifetime: lifetime, timeScale: scale)
    }

    func testShotUsesLifetime() {
        XCTAssertEqual(shot("A").expiresAt, t0.addingTimeInterval(86_400))
        var ledger = Ledger()
        XCTAssertTrue(ledger.add(shot("A")))
        XCTAssertEqual(ledger.shots.count, 1)
    }

    func testEveryLifetimeChoice() {
        let expected: [Lifetime: TimeInterval?] = [.oneHour: 3600, .oneDay: 86_400, .threeDays: 259_200, .sevenDays: 604_800, .never: nil]
        for (lifetime, seconds) in expected { XCTAssertEqual(lifetime.seconds, seconds, lifetime.label) }
        XCTAssertEqual(Lifetime.default, .oneDay)
    }

    func testNeverIsKeptAndNeverExpires() {
        var ledger = Ledger()
        let forever = shot("A", .never)
        XCTAssertNil(forever.expiresAt)
        ledger.add(forever)
        XCTAssertTrue(ledger.expired(at: t0.addingTimeInterval(10 * 365 * 86_400)).isEmpty)
        XCTAssertNil(forever.remaining(at: t0))
        XCTAssertEqual(ledger.summary(at: t0), "1 photo.")
    }

    func testDuplicateIdIgnored() {
        var ledger = Ledger()
        ledger.add(shot("A", .oneHour))
        XCTAssertFalse(ledger.add(shot("A", at: 5)))
        XCTAssertEqual(ledger.shots.count, 1)
    }

    func testExpiryBoundary() {
        var ledger = Ledger()
        ledger.add(shot("A", .oneHour))
        XCTAssertTrue(ledger.expired(at: t0.addingTimeInterval(3599)).isEmpty)
        XCTAssertEqual(ledger.expired(at: t0.addingTimeInterval(3600)).map(\.id), ["A"])
    }

    func testFastForwardScalesLifetime() {
        XCTAssertEqual(shot("A", scale: 3600).expiresAt, t0.addingTimeInterval(24))
        XCTAssertEqual(shot("B", .oneHour, scale: 0).expiresAt, t0.addingTimeInterval(3600), "a bad scale falls back to real time")
    }

    func testRemoveExpiredTakesOnlyExpired() {
        var ledger = Ledger()
        ledger.add(shot("old1", .oneHour))
        ledger.add(shot("old2", at: 10, .oneHour))
        ledger.add(shot("fresh", at: 3000, .oneHour))
        ledger.add(shot("forever", .never))
        let gone = ledger.removeExpired(at: t0.addingTimeInterval(3700))
        XCTAssertEqual(gone.map(\.id), ["old1", "old2"])
        XCTAssertEqual(Set(ledger.shots.map(\.id)), ["fresh", "forever"])
        XCTAssertEqual(ledger.files, ["fresh.jpg", "forever.jpg"])
        XCTAssertTrue(ledger.removeExpired(at: t0.addingTimeInterval(3700)).isEmpty, "nothing left to expire")
    }

    func testForget() {
        var ledger = Ledger()
        ledger.add(shot("A", .oneHour))
        ledger.add(shot("B", .oneHour))
        ledger.forget(["A", "not-tracked"])
        XCTAssertEqual(ledger.shots.map(\.id), ["B"])
        XCTAssertFalse(ledger.contains("A"))
    }

    func testRecentIsNewestFirst() {
        var ledger = Ledger()
        ledger.add(shot("first"))
        ledger.add(shot("second", at: 60))
        XCTAssertEqual(ledger.recent().map(\.id), ["second", "first"])
    }

    func testNextExpiry() {
        var ledger = Ledger()
        ledger.add(shot("A", .oneHour))
        ledger.add(shot("B", .oneDay))
        ledger.add(shot("C", .never))
        XCTAssertEqual(ledger.nextExpiry(after: t0), t0.addingTimeInterval(3600))
        XCTAssertEqual(ledger.nextExpiry(after: t0.addingTimeInterval(4000)), t0.addingTimeInterval(86_400))
        XCTAssertNil(ledger.nextExpiry(after: t0.addingTimeInterval(90_000)))
    }

    func testLabels() {
        XCTAssertNil(remainingLabel(nil), "no chip for a shot that never expires")
        XCTAssertEqual(remainingLabel(0), "1s")
        XCTAssertEqual(remainingLabel(30), "30s")
        XCTAssertEqual(remainingLabel(59.2), "1m")
        XCTAssertEqual(remainingLabel(45 * 60), "45m")
        XCTAssertEqual(remainingLabel(23 * 3600 + 1), "23h")
        XCTAssertEqual(remainingLabel(3 * 86_400), "3d")
        XCTAssertEqual(remainingPhrase(3600), "Expires in 1 hour")
        XCTAssertEqual(remainingPhrase(2 * 86_400), "Expires in 2 days")
        XCTAssertEqual(remainingPhrase(nil), "Never expires")
    }

    func testSummaryLine() {
        var ledger = Ledger()
        XCTAssertNil(ledger.summary(at: t0), "no shots: the empty state speaks instead")
        ledger.add(shot("A"))
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(3600)), "1 photo. It expires in 23 hours.")
        ledger.add(shot("B", at: 60, .oneHour))
        ledger.add(shot("C", at: 120))
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(60)), "3 photos. Next one expires in 1 hour.")
        XCTAssertEqual(ledger.summary(at: t0.addingTimeInterval(3700)), "3 photos. Next one expires in 22 hours.",
                       "an expired shot does not count as next")
        XCTAssertEqual(Ledger.summary(count: 2, next: nil, now: t0), "2 photos.")
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
        ledger.add(shot("A", .threeDays))
        ledger.add(shot("B", .never))
        file.save(ledger)
        XCTAssertEqual(file.load(), ledger)
        XCTAssertEqual(try file.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true,
                       "the ledger is not backed up either")
        try Data("not json".utf8).write(to: file.url)
        XCTAssertEqual(file.load(), Ledger(), "a corrupt file never crashes; it loads empty")
        file.reset()
        XCTAssertEqual(file.load(), Ledger())
    }

    /// The Photos-album version's ledger (PhotoKit identifiers, no version, no file names) loads empty.
    func testOldFormatLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = LedgerFile(url: dir.appendingPathComponent("ledger.json"))
        let old = #"{"shots":[{"id":"9F2C1A7E-1111-2222-3333-444455556666/L0/001","capturedAt":800000000,"expiresAt":800086400}]}"#
        try Data(old.utf8).write(to: file.url)
        XCTAssertEqual(file.load(), Ledger())
        let future = #"{"version":99,"shots":[]}"#
        try Data(future.utf8).write(to: file.url)
        XCTAssertEqual(file.load(), Ledger(), "an unknown version loads empty too")
    }

    /// A ledger path that exists but cannot be read is reported as unreadable, not as empty.
    func testUnreadableIsNil() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("ledger.json")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)   // a folder, not a file
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(LedgerFile(url: path).load())
    }
}
