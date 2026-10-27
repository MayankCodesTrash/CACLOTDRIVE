import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Best-effort privacy step before anything leaves the phone: pixelates faces and any text
/// (which covers license plates), then downsizes. It can miss things, so the UI still warns the user.
enum PrivacyRedactor {
    struct Result {
        let image: UIImage
        let regionsBlurred: Int
    }

    nonisolated static func redact(_ image: UIImage, coverBoxes: [PlateBox] = [], maxDimension: CGFloat = 1280) async -> Result {
        await Task.detached(priority: .userInitiated) {
            redactSync(image, coverBoxes: coverBoxes, maxDimension: maxDimension)
        }.value
    }

    nonisolated static func redactSync(_ image: UIImage, coverBoxes: [PlateBox] = [], maxDimension: CGFloat) -> Result {
        // Boxes the user drew are covered with solid black first, so nothing under them survives the later steps.
        let resized = cover(downscale(image, maxDimension: maxDimension), with: coverBoxes)
        guard let cgImage = resized.cgImage else { return Result(image: resized, regionsBlurred: coverBoxes.count) }

        let faces = VNDetectFaceRectanglesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([faces, text])

        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        var boxes: [CGRect] = []
        for observation in (faces.results ?? []) { boxes.append(observation.boundingBox) }
        for observation in (text.results ?? []) { boxes.append(observation.boundingBox) }
        guard !boxes.isEmpty else { return Result(image: resized, regionsBlurred: coverBoxes.count) }

        // Vision boxes are normalized with a bottom-left origin, which matches Core Image.
        let rects = boxes.map { box -> CGRect in
            let rect = CGRect(x: box.minX * width, y: box.minY * height, width: box.width * width, height: box.height * height)
            return rect.insetBy(dx: -rect.width * 0.12, dy: -rect.height * 0.2).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        }

        var output = CIImage(cgImage: cgImage)
        for rect in rects where rect.width > 2 && rect.height > 2 {
            let filter = CIFilter.pixellate()
            filter.inputImage = output.clampedToExtent()
            filter.scale = Float(max(8, min(rect.width, rect.height) / 5))
            filter.center = CGPoint(x: rect.midX, y: rect.midY)
            if let pixelated = filter.outputImage?.cropped(to: rect) {
                output = pixelated.composited(over: output)
            }
        }

        let context = CIContext()
        guard let result = context.createCGImage(output, from: CIImage(cgImage: cgImage).extent) else {
            return Result(image: resized, regionsBlurred: coverBoxes.count)
        }
        return Result(image: UIImage(cgImage: result), regionsBlurred: rects.count + coverBoxes.count)
    }

    /// Fills each box (normalized, top-left origin) with solid black, slightly enlarged to cover the edges.
    nonisolated static func cover(_ image: UIImage, with boxes: [PlateBox]) -> UIImage {
        guard !boxes.isEmpty else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            UIColor.black.setFill()
            for box in boxes {
                let rect = box.rect(in: image.size)
                context.fill(rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.08))
            }
        }
    }

    nonisolated private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
