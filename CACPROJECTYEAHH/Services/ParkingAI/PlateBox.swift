import UIKit
import Vision

/// A rectangle the user drew over a license plate. Normalized to the photo with a top-left origin,
/// so it survives resizing. These are painted solid black before the photo is sent anywhere.
struct PlateBox: Codable, Equatable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    nonisolated static let minimumSide = 0.03

    nonisolated func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    /// Builds a box from two corners in a view of `size`, in any drag direction, clamped to the photo.
    nonisolated init(from a: CGPoint, to b: CGPoint, in size: CGSize) {
        let x0 = min(max(min(a.x, b.x) / size.width, 0), 1), x1 = min(max(max(a.x, b.x) / size.width, 0), 1)
        let y0 = min(max(min(a.y, b.y) / size.height, 0), 1), y1 = min(max(max(a.y, b.y) / size.height, 0), 1)
        self.init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    nonisolated init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// Moved by a fraction of the photo, staying inside it.
    nonisolated func moved(dx: Double, dy: Double) -> PlateBox {
        var copy = self
        copy.x = min(max(x + dx, 0), 1 - width)
        copy.y = min(max(y + dy, 0), 1 - height)
        return copy
    }

    /// Same top-left corner, bottom-right corner dragged by a fraction of the photo.
    nonisolated func resized(dw: Double, dh: Double) -> PlateBox {
        var copy = self
        copy.width = min(max(width + dw, Self.minimumSide), 1 - x)
        copy.height = min(max(height + dh, Self.minimumSide), 1 - y)
        return copy
    }

    nonisolated var isUsable: Bool { width >= Self.minimumSide && height >= Self.minimumSide }

    /// Text Vision can see, as starting suggestions the user can keep or delete. Not a plate detector: it finds any text.
    nonisolated static func suggestions(in image: UIImage) async -> [PlateBox] {
        await Task.detached(priority: .userInitiated) { () -> [PlateBox] in
            guard let cgImage = image.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return (request.results ?? []).map { observation in
                let box = observation.boundingBox // bottom-left origin
                return PlateBox(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
            .filter(\.isUsable)
        }.value
    }
}
