import UIKit

/// Repaints a palette texture's body-paint swatches in a new color while keeping their light-to-dark shading.
enum PaletteRecolor {
    /// `regions` are [x, y, width, height] in pixels, origin top-left.
    nonisolated static func recolor(_ base: UIImage, regions: [[Int]], toHex hex: String) -> UIImage? {
        guard let cgImage = base.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        let target = (r: Double((value >> 16) & 0xFF), g: Double((value >> 8) & 0xFF), b: Double(value & 0xFF))

        func luminance(_ i: Int) -> Double {
            0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        }

        for region in regions where region.count == 4 {
            let x0 = max(0, region[0]), y0 = max(0, region[1])
            let x1 = min(width, region[0] + region[2]), y1 = min(height, region[1] + region[3])
            guard x1 > x0, y1 > y0 else { continue }

            var total = 0.0, count = 0.0
            for y in y0..<y1 { for x in x0..<x1 { total += luminance((y * width + x) * 4); count += 1 } }
            let reference = max(total / count, 1)

            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * width + x) * 4
                    let shade = min(1.35, luminance(i) / reference)
                    pixels[i] = UInt8(max(0, min(255, target.r * shade)))
                    pixels[i + 1] = UInt8(max(0, min(255, target.g * shade)))
                    pixels[i + 2] = UInt8(max(0, min(255, target.b * shade)))
                }
            }
        }
        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output)
    }
}
