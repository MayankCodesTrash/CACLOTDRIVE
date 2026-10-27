import UIKit
import Vision
import CoreImage

protocol BackgroundRemoving {
    func cutout(_ image: UIImage) async throws -> UIImage
}

/// Isolates the car from its photo using Apple's Vision foreground segmentation (iOS 17).
/// Images that already have a transparent background are only cropped.
struct VehicleBackgroundRemovalService: BackgroundRemoving {
    #if DEBUG
    nonisolated(unsafe) static var lastDebugNote = ""
    nonisolated var lastDebugNote: String { get { Self.lastDebugNote } nonmutating set { Self.lastDebugNote = newValue } }
    #endif

    func cutout(_ image: UIImage) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            try Self.process(image)
        }.value
    }

    nonisolated static func process(_ image: UIImage) throws -> UIImage {
        let normalized = normalize(image, maxDimension: 1600)
        guard let cgImage = normalized.cgImage else { throw VehicleImageError.badImage }

        if hasUsableTransparency(cgImage) {
            guard let trimmed = trimToOpaqueBounds(normalized) else { throw VehicleImageError.badImage }
            return trimmed
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch {
            #if DEBUG
            print("Vision perform failed: \(error)")
            lastDebugNote = "perform failed: \(error)"
            #endif
            throw VehicleImageError.cutoutFailed
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            #if DEBUG
            lastDebugNote = "no foreground instances found"
            #endif
            throw VehicleImageError.cutoutFailed
        }

        // A photo can contain several objects. Keep the biggest one, which is the car in a car photo.
        let chosen = largestInstance(in: observation) ?? observation.allInstances
        guard let buffer = try? observation.generateMaskedImage(ofInstances: chosen, from: handler, croppedToInstancesExtent: false) else {
            throw VehicleImageError.cutoutFailed
        }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ci, from: ci.extent) else { throw VehicleImageError.cutoutFailed }
        let masked = UIImage(cgImage: output)

        guard let trimmed = trimToOpaqueBounds(masked), let trimmedCG = trimmed.cgImage else { throw VehicleImageError.poorCutout }
        // Reject results that are almost nothing or almost the whole frame: the mask probably missed the car.
        let kept = Double(trimmedCG.width * trimmedCG.height) / Double(cgImage.width * cgImage.height)
        let aspect = Double(trimmedCG.width) / Double(max(trimmedCG.height, 1))
        guard kept > 0.06, aspect > 1.0, aspect < 4.0 else { throw VehicleImageError.poorCutout }
        return trimmed
    }

    // MARK: Helpers

    nonisolated static func normalize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private nonisolated static func largestInstance(in observation: VNInstanceMaskObservation) -> IndexSet? {
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask), stride = CVPixelBufferGetBytesPerRow(mask)
        var counts = [Int](repeating: 0, count: 256)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { counts[Int(row[x])] += 1 }
        }
        guard let best = (1..<256).max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else { return nil }
        return IndexSet(integer: best)
    }

    /// True when the picture already has a see-through background: transparent corners and a real amount of transparency.
    nonisolated static func hasUsableTransparency(_ cgImage: CGImage) -> Bool {
        guard let pixels = rgba(cgImage) else { return false }
        let w = cgImage.width, h = cgImage.height
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * w + x) * 4 + 3] }
        let corners = [alpha(0, 0), alpha(w - 1, 0), alpha(0, h - 1), alpha(w - 1, h - 1)]
        guard corners.filter({ $0 < 16 }).count >= 3 else { return false }
        var transparent = 0
        for i in stride(from: 3, to: pixels.count, by: 16) where pixels[i] < 16 { transparent += 1 }
        return Double(transparent) / Double(pixels.count / 16) > 0.08
    }

    nonisolated static func trimToOpaqueBounds(_ image: UIImage, padding: Int = 6) -> UIImage? {
        guard let cg = image.cgImage, let pixels = rgba(cg) else { return nil }
        let w = cg.width, h = cg.height
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 12 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let x0 = max(0, minX - padding), y0 = max(0, minY - padding)
        let rect = CGRect(x: x0, y: y0, width: min(w, maxX + padding + 1) - x0, height: min(h, maxY + padding + 1) - y0)
        return cg.cropping(to: rect).map { UIImage(cgImage: $0) }
    }

    private nonisolated static func rgba(_ cgImage: CGImage) -> [UInt8]? {
        let w = cgImage.width, h = cgImage.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }
}
