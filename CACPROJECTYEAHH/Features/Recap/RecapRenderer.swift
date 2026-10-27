import SwiftUI
import Photos

@MainActor
enum RecapRenderer {
    /// Renders the recap at 3x (1080 x 1350). ImageRenderer cannot draw MapKit views,
    /// which is why recaps use the custom route line instead.
    static func image(style: RecapStyle, content: RecapContent) -> UIImage? {
        let renderer = ImageRenderer(content: RecapCard(style: style, content: content))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

enum PhotoSaver {
    /// Saves to the photo library using add-only access.
    static func save(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }
}
