import UIKit

enum ImageTools {
    /// Downscales and re-encodes as JPEG. Re-encoding drops EXIF metadata such as GPS location.
    static func prepared(_ data: Data, maxDimension: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}
