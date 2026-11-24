@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// The viewfinder and shutter. `RealCamera` uses AVFoundation; `MockCamera` draws generated frames so the
/// whole app can be driven in the simulator, which has no camera.
@MainActor
protocol Camera: AnyObject {
    var isMock: Bool { get }
    var position: AVCaptureDevice.Position { get }
    var hasFlash: Bool { get }
    var maxZoom: CGFloat { get }
    /// Configure the session in the background without starting it, so opening the camera is quick.
    func prepare()
    func start()
    func stop()
    func flip()
    func setZoom(_ factor: CGFloat)
    /// A picture of what the shutter is about to save, for the thumbnail the moment the shutter is
    /// pressed. `nil` when there is none yet (the real camera: its preview arrives with the photo).
    func instantPreview() -> UIImage?
    /// Takes one photo: the encoded image data (HEIC or JPEG) and, when the camera offers one, a small
    /// upright preview that arrives with it (well before the file is written).
    func capture(flash: Bool) async throws -> CapturedPhoto
}

struct CapturedPhoto {
    let data: Data
    let preview: UIImage?
}

enum CameraError: Error { case notReady, noData }

enum CameraAccess {
    case notAsked, granted, denied

    static var current: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notAsked
        case .authorized: return .granted
        default: return .denied
        }
    }

    static func request() async -> CameraAccess {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return current
    }
}

// MARK: - Real camera

/// AVFoundation camera. Everything that can block (configuring, starting and stopping the session,
/// capturing) runs on `queue`, never on the main thread. UI-facing state lives on the main actor.
///
/// Orientation: the UI is portrait only. An `AVCaptureDevice.RotationCoordinator` (iOS 17) supplies two
/// angles. The preview angle is observed (KVO, delivered on the main queue) and applied to the preview
/// layer's connection whenever it or the connection changes. The capture angle is read at the moment of
/// each shot and applied to the photo output's connection, which records it as the Exif orientation.
/// Front camera photos are saved unmirrored, like the system Camera's default ("Mirror Front Camera" off);
/// the preview stays mirrored, as it does there.
@MainActor
final class RealCamera: NSObject, Camera {
    let isMock = false
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var device: AVCaptureDevice?
    private var photoDimensions: CMVideoDimensions?
    private var prepared = false
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var previewAngleObservation: NSKeyValueObservation?
    private var pending: [Int64: CheckedContinuation<CapturedPhoto, Error>] = [:]
    weak var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { if previewLayer !== oldValue { makeRotationCoordinator() } }
    }

    private(set) var position: AVCaptureDevice.Position = .back
    var hasFlash: Bool { device?.hasFlash ?? false }
    var maxZoom: CGFloat { min(device?.maxAvailableVideoZoomFactor ?? 1, 10) }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        reconfigure(to: position)
    }

    func start() {
        prepare()
        let session = self.session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func flip() {
        position = position == .back ? .front : .back
        reconfigure(to: position)
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor, min(factor, maxZoom))
        queue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }

    private func reconfigure(to position: AVCaptureDevice.Position) {
        let session = self.session, output = self.output
        queue.async {
            let setup = Self.configure(session: session, output: output, position: position)
            DispatchQueue.main.async { self.didConfigure(setup) }
        }
    }

    private struct Setup {
        let device: AVCaptureDevice
        let dimensions: CMVideoDimensions?
    }

    /// Runs on `queue`. Photo preset, one camera input, the photo output at the device's largest photo size
    /// and best quality, front photos unmirrored.
    private nonisolated static func configure(session: AVCaptureSession, output: AVCapturePhotoOutput,
                                              position: AVCaptureDevice.Position) -> Setup? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        session.beginConfiguration()
        if session.sessionPreset != .photo, session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        let old = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        old.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else {
            old.forEach { if session.canAddInput($0) { session.addInput($0) } }
            session.commitConfiguration()
            return nil
        }
        session.addInput(input)
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        // After the commit, so the device's active format is the one the photo preset chose.
        // Full sensor resolution: the output has to be told, or photos come out at the smallest size.
        let dimensions = CaptureMath.largest(device.activeFormat.supportedMaxPhotoDimensions)
        if let dimensions, output.maxPhotoDimensions.width != dimensions.width || output.maxPhotoDimensions.height != dimensions.height {
            output.maxPhotoDimensions = dimensions
        }
        if output.maxPhotoQualityPrioritization != .quality { output.maxPhotoQualityPrioritization = .quality }
        // Lets the next shot start while the last one is still processing, for quick repeat shots.
        if output.isZeroShutterLagSupported, !output.isZeroShutterLagEnabled { output.isZeroShutterLagEnabled = true }
        if output.isResponsiveCaptureSupported, !output.isResponsiveCaptureEnabled { output.isResponsiveCaptureEnabled = true }
        // Photo connections record mirroring as an Exif tag. Pin it off so front shots read like the
        // system Camera's default, instead of whatever automatic adjustment picks.
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        return Setup(device: device, dimensions: dimensions)
    }

    private func didConfigure(_ setup: Setup?) {
        guard let setup else {
            prepared = false   // try again on the next start
            QALog.write("camera: configure failed")
            return
        }
        device = setup.device
        photoDimensions = setup.dimensions
        makeRotationCoordinator()
        let size = setup.dimensions.map { "\($0.width)x\($0.height)" } ?? "default"
        QALog.write("camera: \(position == .front ? "front" : "back") ready, photo size \(size)")
    }

    // MARK: Rotation

    /// A new coordinator whenever the device or the preview layer changes (AVCam does the same on flip).
    private func makeRotationCoordinator() {
        previewAngleObservation = nil
        guard let device else {
            rotation = nil
            return
        }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        previewAngleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            // Documented to arrive on the main queue; hop there anyway if it ever does not.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.applyPreviewAngle() }
            } else {
                DispatchQueue.main.async { self?.applyPreviewAngle() }
            }
        }
    }

    /// Also called when the preview view lands in a window, and after each configuration, because the
    /// preview layer's connection only exists once the layer has a session with a camera input.
    func applyPreviewAngle() {
        guard let rotation, let connection = previewLayer?.connection else { return }
        let angle = rotation.videoRotationAngleForHorizonLevelPreview
        if connection.videoRotationAngle != angle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: Capture

    /// The live preview cannot be snapshotted; the photo's own small preview arrives with the capture.
    func instantPreview() -> UIImage? { nil }

    func capture(flash: Bool) async throws -> CapturedPhoto {
        guard device != nil else { throw CameraError.notReady }
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        if let photoDimensions { settings.maxPhotoDimensions = photoDimensions }
        settings.photoQualityPrioritization = .quality
        if flash, output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
        // A small preview delivered with the photo, for the thumbnail, so nothing waits for the full image
        // to be decoded.
        if let format = settings.availablePreviewPhotoPixelFormatTypes.first {
            settings.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String: format,
                kCVPixelBufferWidthKey as String: Int(ShotStore.thumbnailPixels),
                kCVPixelBufferHeightKey as String: Int(ShotStore.thumbnailPixels),
            ]
        }
        let id = settings.uniqueID
        let session = self.session, output = self.output
        let photo: CapturedPhoto = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            queue.async {
                guard session.isRunning else {
                    DispatchQueue.main.async { self.finish(id, .failure(CameraError.notReady)) }
                    return
                }
                if let angle, let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                output.capturePhoto(with: settings, delegate: self)
            }
        }
        if QA.log {
            let expected = angle.flatMap(CaptureMath.exifOrientation(forRotationAngle:)).map { "\($0.rawValue)" } ?? "-"
            let info = PhotoInfo(data: photo.data).map(\.description) ?? "unreadable"
            QALog.write("camera: \(position == .front ? "front" : "back") angle=\(angle.map { "\(Int($0))" } ?? "-") expect exif=\(expected) got \(info)")
        }
        return photo
    }

    fileprivate func finish(_ id: Int64, _ result: Result<CapturedPhoto, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}

extension RealCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let result: Result<CapturedPhoto, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            // The preview's pixels are as the sensor read them; the photo's Exif orientation makes it upright.
            let raw = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
            let orientation = CaptureMath.imageOrientation(CGImagePropertyOrientation(rawValue: raw) ?? .up)
            let preview = photo.previewCGImageRepresentation().map { UIImage(cgImage: $0, scale: 1, orientation: orientation) }
            result = .success(CapturedPhoto(data: data, preview: preview))
        } else {
            result = .failure(CameraError.noData)
        }
        Task { @MainActor in self.finish(id, result) }
    }
}

/// Live preview layer for the real camera. The view's backing layer IS the preview layer, so it always
/// has the view's bounds; aspect fill in a 3:4 frame matches the 4:3 photo exactly.
struct CameraPreview: UIViewRepresentable {
    let camera: RealCamera

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?() }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = camera.session
        camera.previewLayer = view.previewLayer
        view.onWindow = { [weak camera] in camera?.applyPreviewAngle() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Mock camera

/// QA camera: an animated test pattern in the viewfinder, and capture renders a real JPEG with a
/// timestamp and counter, so saving, thumbnails and expiry are exercised end to end in the simulator.
@MainActor
final class MockCamera: Camera {
    let isMock = true
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var zoom: CGFloat = 1
    private var count = 0
    /// The shot number the next capture gets (the demo viewfinder shows that scene).
    var nextNumber: Int { count + 1 }
    let hasFlash = true
    let maxZoom: CGFloat = 5

    func prepare() {}
    func start() {}
    func stop() {}
    func flip() { position = position == .back ? .front : .back }
    func setZoom(_ factor: CGFloat) { zoom = max(1, min(factor, maxZoom)) }

    /// The frame the next capture will save, drawn small, so the thumbnail shows at once.
    func instantPreview() -> UIImage? {
        #if DEBUG
        if QA.demoPhotos { return MockFrames.shrink(DemoScenes.photo(nextNumber)) }
        #endif
        return MockFrames.photo(number: nextNumber, date: Date(), front: position == .front, zoom: zoom, scale: 0.3)
    }

    /// Draws and encodes off the main thread, so quick taps never wait on each other.
    func capture(flash: Bool) async throws -> CapturedPhoto {
        count += 1
        let number = count, front = position == .front, zoom = zoom, date = Date()
        var demo: UIImage?
        #if DEBUG
        if QA.demoPhotos { demo = DemoScenes.photo(number) }
        #endif
        let source = demo
        let data = await Task.detached(priority: .userInitiated) {
            let image = source ?? MockFrames.photo(number: number, date: date, front: front, zoom: zoom)
            return image.jpegData(compressionQuality: 0.85)
        }.value
        guard let data else { throw CameraError.noData }
        return CapturedPhoto(data: data, preview: nil)
    }
}

enum MockFrames {
    static let palette: [(UIColor, UIColor)] = [
        (.systemTeal, .systemIndigo), (.systemOrange, .systemPink), (.systemGreen, .systemBlue), (.systemPurple, .systemRed),
    ]

    /// A 1200 x 1600 test photo; `scale` < 1 draws the same picture with fewer pixels.
    static func photo(number: Int, date: Date, front: Bool, zoom: CGFloat, scale: CGFloat = 1) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let colors = palette[(number - 1) % palette.count]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let lines = ["Mock shot #\(number)", formatter.string(from: date), front ? "front" : "back", String(format: "%.1fx", zoom)]
        return render(size: size, top: colors.0, bottom: colors.1, lines: lines, scale: scale)
    }

    /// The same picture at 30% of its pixels.
    static func shrink(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.3
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
    }

    static func render(size: CGSize, top: UIColor, bottom: UIColor, lines: [String], scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: style,
            ]
            let text = lines.joined(separator: "\n") as NSString
            let box = text.boundingRect(with: CGSize(width: size.width - 80, height: size.height), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            text.draw(in: CGRect(x: 40, y: (size.height - box.height) / 2, width: size.width - 80, height: box.height), withAttributes: attrs)
        }
    }
}

/// Animated stand-in for the viewfinder in mock mode.
struct MockPreview: View {
    let zoom: CGFloat
    let front: Bool
    var next = 1

    var body: some View {
        #if DEBUG
        if QA.demoPhotos {
            // The scene the shutter will save, filling the 3:4 viewfinder like a live preview.
            Image(uiImage: DemoScenes.photo(next))
                .resizable()
                .scaledToFill()
                .scaleEffect(zoom)
                .accessibilityIdentifier("mock-preview")
        } else {
            pattern
        }
        #else
        pattern
        #endif
    }

    private var pattern: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(hue: (t / 20).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.6),
                                        Color(hue: (t / 20 + 0.3).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 3)
                    .frame(width: 140 * zoom, height: 140 * zoom)
                    .offset(x: CGFloat(sin(t)) * 60, y: CGFloat(cos(t * 0.7)) * 80)
                VStack(spacing: 6) {
                    Text("Mock camera").font(.headline)
                    Text(front ? "front" : "back").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .accessibilityIdentifier("mock-preview")
    }
}
