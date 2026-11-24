import Photos

/// The app's only PhotoKit code: Save to Photos for one shot, when the user taps it. Asks for add-only
/// access (the app can add photos, never see or change the library), and only at that moment.
enum PhotoSaver {
    enum SaveError: Error { case noAccess }

    /// Adds a copy of the file to the library. Throws `noAccess` if the user said no (now or before).
    static func save(fileAt url: URL, takenAt date: Date) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.noAccess }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
            request.creationDate = date
        }
    }
}
