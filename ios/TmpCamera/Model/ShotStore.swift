import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The photo files, in the app's own container: `Application Support/Shots/`. Nothing here touches the
/// Photos library. The folder is excluded from iCloud and computer backups. Each photo is written once, as
/// the camera produced it (HEIC or JPEG, orientation in its Exif tag), with file protection
/// `completeUnlessOpen`: unreadable while the phone is locked, but a shot that finishes saving just as the
/// phone locks can still be written.
///
/// Thumbnails are made with ImageIO (downsampled, orientation applied) and kept in memory only.
final class ShotStore: @unchecked Sendable {
    let dir: URL
    /// Longest side of a grid or camera thumbnail, in pixels.
    static let thumbnailPixels: CGFloat = 480

    private let thumbnails = NSCache<NSString, UIImage>()
    private let lock = NSLock()

    init(dir: URL) {
        self.dir = dir
        thumbnails.countLimit = 300
    }

    static var standard: ShotStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ShotStore(dir: base.appendingPathComponent("Shots", isDirectory: true))
    }

    enum StoreError: Error { case noName }

    func url(for file: String) -> URL { dir.appendingPathComponent(file) }

    /// Creates the folder if needed and marks it excluded from backup (which covers everything in it).
    func prepareFolder() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var copy = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try copy.setResourceValues(values)
    }

    /// Writes the photo data as is and returns its file name, "Tmp 2026-11-24 at 09.41.07.heic" (" 2", " 3"
    /// when several shots share a second). Also makes its thumbnail from the data in memory, so nothing is
    /// read back from disk. Runs off the main thread.
    func write(_ data: Data, id: String, capturedAt: Date) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [self] in
            try prepareFolder()
            let base = "Tmp " + Self.nameFormatter.string(from: capturedAt)
            let ext = Self.fileExtension(for: data)
            // .withoutOverwriting makes the name check and the write one step; the lock keeps two quick
            // shots from racing for the same name.
            let written: String? = try lock.withLock {
                for n in 1...999 {
                    let name = n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)"
                    do {
                        try data.write(to: url(for: name), options: [.withoutOverwriting, .completeFileProtectionUnlessOpen])
                        return name
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        continue
                    }
                }
                return nil
            }
            guard let written else { throw StoreError.noName }
            if let thumb = Self.downsample(CGImageSourceCreateWithData(data as CFData, Self.sourceOptions), maxPixels: Self.thumbnailPixels) {
                thumbnails.setObject(thumb, forKey: id as NSString)
            }
            return written
        }.value
    }

    /// Deletes these files. Names only, always inside the Shots folder.
    func delete(_ files: some Sequence<String>) {
        for file in files where !file.isEmpty && !file.contains("/") {
            try? FileManager.default.removeItem(at: url(for: file))
        }
    }

    func forgetThumbnails(_ ids: some Sequence<String>) {
        for id in ids { thumbnails.removeObject(forKey: id as NSString) }
    }

    /// Every file in the Shots folder.
    func allFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    /// Deletes files the ledger does not name (a shot whose save was cut short). Returns how many.
    @discardableResult
    func deleteFiles(notIn keep: Set<String>) -> Int {
        let stray = allFiles().filter { !keep.contains($0) }
        delete(stray)
        return stray.count
    }

    func exists(_ file: String) -> Bool { FileManager.default.fileExists(atPath: url(for: file).path) }

    /// Removes the whole folder (Delete all now, and TMP_RESET).
    func deleteAll() {
        try? FileManager.default.removeItem(at: dir)
        thumbnails.removeAllObjects()
    }

    // MARK: Images

    /// The thumbnail if it is already in memory. Cheap enough to call from a view's body.
    func cachedThumbnail(_ id: String) -> UIImage? { thumbnails.object(forKey: id as NSString) }

    /// The shot's thumbnail, from memory or made from the file off the main thread.
    func thumbnail(id: String, file: String) async -> UIImage? {
        if let hit = cachedThumbnail(id) { return hit }
        let url = url(for: file)
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsample(CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions), maxPixels: Self.thumbnailPixels)
        }.value
        if let image { thumbnails.setObject(image, forKey: id as NSString) }
        return image
    }

    /// The photo at screen size for the viewer, upright. Not cached.
    func displayImage(file: String, maxPixels: CGFloat) async -> UIImage? {
        let url = url(for: file)
        return await Task.detached(priority: .userInitiated) {
            Self.downsample(CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions), maxPixels: maxPixels)
        }.value
    }

    private static let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

    /// An upright image no larger than `maxPixels` on its longest side. The Exif orientation is applied, so
    /// the result needs no further rotation.
    static func downsample(_ source: CGImageSource?, maxPixels: CGFloat) -> UIImage? {
        guard let source else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixels)),
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// "heic" or "jpg", from the data itself.
    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source).map({ UTType($0 as String) }) ?? nil else { return "jpg" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "heic" }
        if type.conforms(to: .jpeg) { return "jpg" }
        return type.preferredFilenameExtension ?? "jpg"
    }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
