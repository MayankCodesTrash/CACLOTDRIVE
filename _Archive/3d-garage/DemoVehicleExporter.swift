#if DEBUG
import SceneKit
import UIKit

/// One-off tool: renders transparent 2D vehicle PNGs from the 3D library, to bundle as offline demo assets.
@MainActor
enum DemoVehicleExporter {
    static let bodies: [(CarBodyStyle, String)] = [
        (.sedan, "kenney-sedan"), (.hatchback, "kenney-hatchback-sports"), (.suv, "kenney-suv"),
        (.pickup, "kenney-truck"), (.coupe, "kenney-sedan-sports"), (.van, "kenney-van"),
    ]
    static let colors: [(String, String)] = [
        ("white", "F2F2EF"), ("black", "1D1F22"), ("silver", "C5CACF"),
        ("red", "C0302B"), ("blue", "2F5FA8"), ("orange", "E98A2B"),
    ]

    static func exportAll() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        for (body, modelID) in bodies {
            for (colorName, hex) in colors {
                let spec = CarSpec(body: body, wheels: .sport, colorHex: hex, libraryModelID: modelID)
                let scene = CarSceneBuilder.makeScene(for: spec, platform: false)
                scene.rootNode.childNode(withName: "car", recursively: false)?.eulerAngles.y = -0.2
                guard let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) else { continue }
                camera.camera?.fieldOfView = 20
                camera.position = SCNVector3(5.6, 1.5, 9.0)

                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.pointOfView = camera
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 2400, height: 1200), antialiasingMode: .multisampling4X)
                guard let trimmed = trimmed(image), let data = trimmed.pngData() else { continue }
                let name = "demo-\(body.rawValue)-\(colorName).png"
                try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name))
            }
        }
    }

    /// Crops to the opaque pixels, with a little padding.
    private static func trimmed(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX, maxY > minY else { return nil }
        let pad = 12
        let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                          width: min(w, maxX + pad) - max(0, minX - pad), height: min(h, maxY + pad) - max(0, minY - pad))
        return cg.cropping(to: rect).map { UIImage(cgImage: $0) }
    }
}
#endif
