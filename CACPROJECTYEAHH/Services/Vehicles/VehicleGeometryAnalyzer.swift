import UIKit

/// What LOT measures from a car cutout so it can be placed in the garage correctly.
/// All positions are fractions (0...1) of the cropped image, measured from its top-left.
///
/// Only things that can be measured reliably from the outline are measured: where the car meets the floor, and how far along the
/// bottom of the picture the car reaches. The far tire can't be told apart from a dark bumper lip using the outline alone, so it
/// isn't guessed at.
struct VehicleGeometry: Equatable {
    /// Where a tire meets the ground.
    struct Contact: Equatable {
        var x: Double
        var y: Double
        /// Width of the flat part of the tire's bottom, as a fraction of the image width.
        var width: Double
    }

    /// The lowest point of the car, which is the tire nearest the camera. Nil only for an empty image.
    var nearContact: Contact?

    /// Horizontal extent of the car's underside (everything within about a quarter of its height of the ground), as fractions.
    var footprint: ClosedRange<Double>

    var contacts: [Contact] { nearContact.map { [$0] } ?? [] }
    var groundY: Double { nearContact?.y ?? 1 }
    var footprintCenterX: Double { (footprint.lowerBound + footprint.upperBound) / 2 }
    var footprintWidth: Double { footprint.upperBound - footprint.lowerBound }
}

struct VehicleAnalysis {
    /// The cutout cropped tight to the car's opaque pixels.
    let image: UIImage
    let geometry: VehicleGeometry
}

enum VehicleGeometryAnalyzer {
    private final class Box { let analysis: VehicleAnalysis?; init(_ a: VehicleAnalysis?) { analysis = a } }
    private nonisolated(unsafe) static let cache = NSCache<UIImage, Box>()

    /// Cached per image instance, so drawing the Garage again doesn't re-measure.
    static func cachedAnalysis(of image: UIImage) -> VehicleAnalysis? {
        if let hit = cache.object(forKey: image) { return hit.analysis }
        let result = analyze(image)
        cache.setObject(Box(result), forKey: image)
        return result
    }

    nonisolated static func analyze(_ image: UIImage) -> VehicleAnalysis? {
        guard let cg = image.cgImage else { return nil }

        // Measure on a small copy. It's plenty for finding bounds and tire contacts.
        let scale = min(1, 360 / CGFloat(max(cg.width, 1)))
        let aw = max(2, Int((CGFloat(cg.width) * scale).rounded())), ah = max(2, Int((CGFloat(cg.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: aw * ah * 4)
        guard let ctx = CGContext(data: &pixels, width: aw, height: ah, bitsPerComponent: 8, bytesPerRow: aw * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: aw, height: ah))
        func opaque(_ x: Int, _ y: Int) -> Bool { pixels[(y * aw + x) * 4 + 3] >= 128 }

        var minX = aw, maxX = -1, minY = ah, maxY = -1
        for y in 0..<ah { for x in 0..<aw where opaque(x, y) {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        guard maxX - minX >= 8, maxY - minY >= 8 else { return nil }

        let inv = 1 / scale
        let crop = CGRect(x: CGFloat(minX) * inv, y: CGFloat(minY) * inv,
                          width: CGFloat(maxX - minX + 1) * inv, height: CGFloat(maxY - minY + 1) * inv)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)).integral
        guard let cropped = cg.cropping(to: crop) else { return nil }

        let width = maxX - minX + 1, height = Double(maxY - minY + 1)
        var profile = [Double](repeating: 0, count: width)
        for column in 0..<width {
            var lowest = -1
            for y in stride(from: maxY, through: minY, by: -1) where opaque(minX + column, y) { lowest = y; break }
            profile[column] = lowest < 0 ? 0 : Double(lowest - minY + 1) / height
        }
        let smooth = smoothed(profile, radius: 2)

        // 4. The lowest flat stretch of the outline is the tire nearest the camera, and the underside's reach gives the footprint.
        let (near, footprint) = measureGround(smooth, width: width)
        return VehicleAnalysis(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up),
                               geometry: VehicleGeometry(nearContact: near, footprint: footprint))
    }

    nonisolated private static func smoothed(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in
            let lo = max(0, i - radius), hi = min(values.count - 1, i + radius)
            return values[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
    }

    nonisolated private static func measureGround(_ profile: [Double], width: Int) -> (VehicleGeometry.Contact?, ClosedRange<Double>) {
        guard let lowest = profile.max(), lowest > 0 else { return (nil, 0...1) }

        // Columns within a hair of the lowest point, grouped into runs. The widest run is the tire's flat contact.
        let tolerance = 0.012
        var best: ClosedRange<Int>?
        var start: Int?
        for i in profile.indices {
            let near = profile[i] >= lowest - tolerance
            if near, start == nil { start = i }
            if (!near || i == profile.count - 1), let s = start {
                let end = near ? i : i - 1
                if best == nil || (end - s) > (best!.upperBound - best!.lowerBound) { best = s...end }
                start = nil
            }
        }
        let contact = best.map {
            VehicleGeometry.Contact(x: (Double($0.lowerBound + $0.upperBound) / 2 + 0.5) / Double(width), y: lowest,
                                    width: max(0.02, Double($0.count) / Double(width)))
        }

        let underside = profile.indices.filter { profile[$0] >= lowest - 0.28 }
        let first = underside.first ?? 0, last = underside.last ?? (width - 1)
        return (contact, (Double(first) / Double(width))...(Double(last + 1) / Double(width)))
    }
}
