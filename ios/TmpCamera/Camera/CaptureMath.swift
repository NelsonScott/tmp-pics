import AVFoundation
import ImageIO
import UIKit

/// Pure helpers behind the real camera, kept apart so they are unit tested (the simulator has no camera).
enum CaptureMath {
    /// The biggest photo size a camera format offers, by pixel count. The photo output must be told this
    /// explicitly: `AVCapturePhotoSettings.maxPhotoDimensions` defaults to the SMALLEST supported size,
    /// which is 12 MP on a 48 MP sensor.
    static func largest(_ dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        dimensions.max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
    }

    /// The Exif orientation a photo output writes for a connection rotation angle (degrees clockwise),
    /// with mirroring off. The pixels stay as the sensor read them; viewers rotate by this tag.
    static func exifOrientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation? {
        switch Int(angle.rounded()) % 360 {
        case 0: return .up
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return nil
        }
    }

    /// The UIImage orientation that shows an image with this Exif orientation upright.
    static func imageOrientation(_ exif: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch exif {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
}

/// Size and orientation of an encoded photo (JPEG or HEIC), read with ImageIO. Used for the QA log, so a
/// device run shows what was actually saved: pixel size, Exif orientation, and the shape once upright.
struct PhotoInfo: Equatable, CustomStringConvertible {
    let width: Int
    let height: Int
    let orientation: CGImagePropertyOrientation

    init(width: Int, height: Int, orientation: CGImagePropertyOrientation) {
        self.width = width
        self.height = height
        self.orientation = orientation
    }

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let raw = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        self.init(width: w, height: h, orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }

    /// True when the photo, displayed upright, is taller than wide.
    var uprightIsPortrait: Bool {
        let swapped: Set<CGImagePropertyOrientation> = [.left, .right, .leftMirrored, .rightMirrored]
        return swapped.contains(orientation) ? width > height : height > width
    }

    var isMirrored: Bool { [.upMirrored, .downMirrored, .leftMirrored, .rightMirrored].contains(orientation) }

    var description: String {
        let mp = Double(width * height) / 1_000_000
        return "\(width)x\(height) (\(String(format: "%.1f", mp)) MP) exif=\(orientation.rawValue) "
            + "upright=\(uprightIsPortrait ? "portrait" : "landscape")\(isMirrored ? " mirrored" : "")"
    }
}
