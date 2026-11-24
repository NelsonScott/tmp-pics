import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TmpCamera

/// Test images made with ImageIO, so their type and Exif orientation are exactly known.
enum TestImages {
    /// A `width` x `height` image encoded as `type`, with the Exif orientation `exif`.
    static func data(width: Int, height: Int, type: UTType = .jpeg, exif: UInt32 = 1) -> Data? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: exif] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func jpeg() -> Data { data(width: 400, height: 300)! }
}

final class ShotStoreTests: XCTestCase {
    var dir: URL!
    var store: ShotStore!
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Shots")
        store = ShotStore(dir: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    func testWriteKeepsTheOriginalBytes() async throws {
        let data = TestImages.jpeg()
        let name = try await store.write(data, id: "A", capturedAt: t0)
        XCTAssertTrue(name.hasPrefix("Tmp "), name)
        XCTAssertTrue(name.hasSuffix(".jpg"), name)
        XCTAssertEqual(try Data(contentsOf: store.url(for: name)), data, "the file is exactly what the camera made")
        XCTAssertNotNil(store.cachedThumbnail("A"), "the thumbnail is ready in memory as soon as the write returns")
        XCTAssertEqual(store.allFiles(), [name])
    }

    func testHEICKeepsItsType() async throws {
        guard let heic = TestImages.data(width: 400, height: 300, type: .heic) else {
            throw XCTSkip("no HEIC encoder on this simulator")
        }
        XCTAssertEqual(ShotStore.fileExtension(for: heic), "heic")
        let name = try await store.write(heic, id: "H", capturedAt: t0)
        XCTAssertTrue(name.hasSuffix(".heic"), name)
    }

    func testSameSecondGetsANewName() async throws {
        let a = try await store.write(TestImages.jpeg(), id: "A", capturedAt: t0)
        let b = try await store.write(TestImages.jpeg(), id: "B", capturedAt: t0)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(b.hasSuffix(" 2.jpg"), b)
        XCTAssertEqual(Set(store.allFiles()), [a, b])
    }

    func testFolderIsExcludedFromBackup() async throws {
        _ = try await store.write(TestImages.jpeg(), id: "A", capturedAt: t0)
        XCTAssertEqual(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testFileProtection() async throws {
        let name = try await store.write(TestImages.jpeg(), id: "A", capturedAt: t0)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.url(for: name).path)
        guard let protection = attrs[.protectionKey] as? FileProtectionType else {
            throw XCTSkip("this simulator does not report file protection")
        }
        XCTAssertEqual(protection, .completeUnlessOpen)
    }

    func testDeleteAndStrayFiles() async throws {
        let keep = try await store.write(TestImages.jpeg(), id: "A", capturedAt: t0)
        let gone = try await store.write(TestImages.jpeg(), id: "B", capturedAt: t0.addingTimeInterval(1))
        try Data("partial".utf8).write(to: store.url(for: "stray.heic"))
        XCTAssertEqual(store.deleteFiles(notIn: [keep, gone]), 1)
        XCTAssertEqual(Set(store.allFiles()), [keep, gone])
        store.delete([gone])
        XCTAssertEqual(store.allFiles(), [keep])
        XCTAssertFalse(store.exists(gone))
    }

    func testDeleteNeverLeavesTheFolder() throws {
        let outside = dir.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outside)
        store.delete(["../outside.txt", ""])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testDeleteAll() async throws {
        _ = try await store.write(TestImages.jpeg(), id: "A", capturedAt: t0)
        store.deleteAll()
        XCTAssertTrue(store.allFiles().isEmpty)
        XCTAssertNil(store.cachedThumbnail("A"))
    }

    /// Exif orientation 6 (rotate 90 clockwise to view) on 400 x 300 pixels: upright it is 300 x 400.
    func testThumbnailsAreUpright() async throws {
        let data = try XCTUnwrap(TestImages.data(width: 400, height: 300, exif: 6))
        let name = try await store.write(data, id: "R", capturedAt: t0)
        let cached = try XCTUnwrap(store.cachedThumbnail("R"))
        XCTAssertLessThan(cached.size.width, cached.size.height)
        store.forgetThumbnails(["R"])
        XCTAssertNil(store.cachedThumbnail("R"))
        let fromFile = await store.thumbnail(id: "R", file: name)
        let thumb = try XCTUnwrap(fromFile)
        XCTAssertLessThan(thumb.size.width, thumb.size.height, "made from the file, still upright")
        let display = await store.displayImage(file: name, maxPixels: 200)
        let big = try XCTUnwrap(display)
        XCTAssertEqual(big.size.height, 200, "downsampled to the longest side asked for")
        XCTAssertEqual(big.size.width, 150)
    }

    func testThumbnailIsSmall() async throws {
        let data = try XCTUnwrap(TestImages.data(width: 4032, height: 3024))
        _ = try await store.write(data, id: "BIG", capturedAt: t0)
        let thumb = try XCTUnwrap(store.cachedThumbnail("BIG"))
        XCTAssertEqual(max(thumb.size.width, thumb.size.height), ShotStore.thumbnailPixels)
    }
}
