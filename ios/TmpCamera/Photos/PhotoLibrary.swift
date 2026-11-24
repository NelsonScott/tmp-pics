import Photos
import UIKit

/// Everything the app does with the Photos library. Read-write access is requested because both
/// putting a shot in a named album and deleting it later need it (add-only access can do neither).
/// With limited access the app still saves, tracks and deletes its own shots; only the album is skipped,
/// because iOS does not let a limited-access app create or fetch albums.
final class PhotoLibrary {
    enum Access: Equatable {
        case notAsked, full, limited, off
    }

    enum SaveError: Error { case noAccess, noIdentifier }

    /// Result of one save: the new asset's identifier and whether it landed in the album.
    struct Saved {
        let id: String
        let inAlbum: Bool
    }

    private let library = PHPhotoLibrary.shared()
    private let imageManager = PHCachingImageManager()
    private var albumIDCache: [String: String] = [:]

    var access: Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notAsked
        case .authorized: return .full
        case .limited: return .limited
        default: return .off
        }
    }

    var canUse: Bool { access == .full || access == .limited }

    func requestAccess() async -> Access {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return access
    }

    // MARK: Saving

    /// Saves JPEG/HEIC data as a new asset, adding it to the album named `albumName` (reused if one exists,
    /// created if missing) when access allows. Creating an asset never shows a system prompt.
    func save(_ data: Data, albumName: String) async throws -> Saved {
        guard canUse else { throw SaveError.noAccess }
        var album: PHAssetCollection?
        if access == .full {
            album = try? await findOrCreateAlbum(named: albumName)
        }
        let box = IDBox()
        try await library.performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            request.creationDate = Date()
            guard let placeholder = request.placeholderForCreatedAsset else { return }
            box.id = placeholder.localIdentifier
            if let album, let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                albumRequest.addAssets([placeholder] as NSArray)
                box.inAlbum = true
            }
        }
        guard let id = box.id else { throw SaveError.noIdentifier }
        return Saved(id: id, inAlbum: box.inAlbum)
    }

    /// The first regular user album with this exact title, or a new one.
    func findOrCreateAlbum(named name: String) async throws -> PHAssetCollection {
        if let id = albumIDCache[name],
           let cached = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
           cached.localizedTitle == name {
            return cached
        }
        if let existing = Self.userAlbums().first(where: { $0.localizedTitle == name }) {
            albumIDCache[name] = existing.localIdentifier
            return existing
        }
        let box = IDBox()
        try await library.performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            box.id = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = box.id,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        else { throw SaveError.noIdentifier }
        albumIDCache[name] = id
        QALog.write("created album \(name)")
        return created
    }

    /// Regular albums the user made (including ones inside folders) that accept new photos. Full access only.
    static func userAlbums() -> [PHAssetCollection] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return [] }
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            if collection.canPerform(.addContent) { albums.append(collection) }
        }
        return albums.sorted { ($0.localizedTitle ?? "").localizedCaseInsensitiveCompare($1.localizedTitle ?? "") == .orderedAscending }
    }

    // MARK: Deleting

    /// Deletes exactly these assets in ONE change, so iOS shows one confirmation for the whole batch.
    /// Callers only ever pass identifiers from the ledger. Returns the identifiers that are now gone from
    /// the library (deleted, or already missing). Throws if the user tapped Don't Allow.
    func delete(_ ids: [String]) async throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var found: [String] = []
        assets.enumerateObjects { asset, _, _ in found.append(asset.localIdentifier) }
        let missing = ids.filter { !found.contains($0) }
        if assets.count > 0 {
            try await library.performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        }
        QALog.write("deleted \(found.count), already gone \(missing.count)")
        return ids
    }

    /// Which of these identifiers still exist (the user may have deleted some in Photos).
    func existing(_ ids: [String]) -> Set<String> {
        guard canUse, !ids.isEmpty else { return Set(ids) }
        var out = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            out.insert(asset.localIdentifier)
        }
        return out
    }

    // MARK: Images

    func image(for id: String, size: CGSize, contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        guard canUse, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: size, contentMode: contentMode, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    #if DEBUG
    /// QA only: put one untracked photo into the album so tests can prove it survives Clear.
    func seedForeignPhoto(albumName: String) async {
        guard access == .full, let album = try? await findOrCreateAlbum(named: albumName) else { return }
        let data = MockFrames.foreignPhoto().jpegData(compressionQuality: 0.8) ?? Data()
        let box = IDBox()
        try? await library.performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            if let placeholder = request.placeholderForCreatedAsset {
                box.id = placeholder.localIdentifier
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
        QALog.write("seeded foreign photo \(box.id ?? "?") in \(albumName)")
    }
    #endif
}

/// Carries identifiers out of a PhotoKit change block.
private final class IDBox: @unchecked Sendable {
    var id: String?
    var inAlbum = false
}
