import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TmpCamera

/// The real camera cannot run in the simulator. These cover the pure pieces it relies on.
final class CaptureMathTests: XCTestCase {
    private func dims(_ w: Int32, _ h: Int32) -> CMVideoDimensions { CMVideoDimensions(width: w, height: h) }

    func testLargestPhotoSizeWins() {
        // Order as a 48 MP iPhone lists them; the default (smallest) would be 12 MP.
        let found = CaptureMath.largest([dims(4032, 3024), dims(8064, 6048), dims(5712, 4284)])
        XCTAssertEqual(found?.width, 8064)
        XCTAssertEqual(found?.height, 6048)
        XCTAssertNil(CaptureMath.largest([]))
    }

    func testRotationAngleToExif() {
        XCTAssertEqual(CaptureMath.exifOrientation(forRotationAngle: 0), .up)
        XCTAssertEqual(CaptureMath.exifOrientation(forRotationAngle: 90), .right, "portrait: the 4:3 sensor image is turned a quarter clockwise")
        XCTAssertEqual(CaptureMath.exifOrientation(forRotationAngle: 180), .down)
        XCTAssertEqual(CaptureMath.exifOrientation(forRotationAngle: 270), .left)
        XCTAssertNil(CaptureMath.exifOrientation(forRotationAngle: 45))
    }

    func testUprightShape() {
        // A landscape sensor buffer tagged "right" is a portrait photo once displayed.
        XCTAssertTrue(PhotoInfo(width: 8064, height: 6048, orientation: .right).uprightIsPortrait)
        XCTAssertFalse(PhotoInfo(width: 8064, height: 6048, orientation: .up).uprightIsPortrait)
        XCTAssertFalse(PhotoInfo(width: 8064, height: 6048, orientation: .down).uprightIsPortrait)
        XCTAssertTrue(PhotoInfo(width: 1200, height: 1600, orientation: .up).uprightIsPortrait)
        XCTAssertTrue(PhotoInfo(width: 4032, height: 3024, orientation: .leftMirrored).isMirrored)
    }

    /// Reads the orientation tag back out of real encoded data, as the QA log does on a device.
    func testPhotoInfoReadsEncodedData() throws {
        let image = MockFrames.render(size: CGSize(width: 400, height: 300), top: .red, bottom: .blue, lines: ["x"])
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let info = try XCTUnwrap(PhotoInfo(data: data as Data))
        XCTAssertEqual(info, PhotoInfo(width: 400, height: 300, orientation: .right))
        XCTAssertTrue(info.uprightIsPortrait)
        XCTAssertEqual(info.description, "400x300 (0.1 MP) exif=6 upright=portrait")
        XCTAssertNil(PhotoInfo(data: Data("nope".utf8)))
    }
}
