import SceneKit
import UIKit

/// Builds a stylized 3D car from simple extruded profiles, or loads an imported .usdz.
/// The stylized car shows body type, paint and wheels. It is not a scan of the real car.
@MainActor
enum CarSceneBuilder {
    private struct Profile {
        let hull: [CGPoint]
        let cabin: [CGPoint]
        let roofX: CGFloat, roofLength: CGFloat, roofY: CGFloat
        let wheelRadius: CGFloat
        let axle: CGFloat
        let width: CGFloat
        let length: CGFloat
        var bed: (x: CGFloat, length: CGFloat, y: CGFloat)? = nil
    }

    private static func profile(for body: CarBodyStyle) -> Profile {
        switch body {
        case .sedan:
            Profile(hull: [(-2.3, 0.30), (-2.3, 0.78), (-1.15, 0.90), (1.45, 0.86), (2.3, 0.62), (2.3, 0.30)].map(CGPoint.init),
                    cabin: [(-1.2, 0.90), (-0.75, 1.45), (0.5, 1.45), (1.2, 0.90)].map(CGPoint.init),
                    roofX: -0.12, roofLength: 1.25, roofY: 1.45, wheelRadius: 0.34, axle: 1.45, width: 1.85, length: 4.6)
        case .hatchback:
            Profile(hull: [(-2.0, 0.30), (-2.0, 0.85), (1.2, 0.85), (2.0, 0.60), (2.0, 0.30)].map(CGPoint.init),
                    cabin: [(-1.95, 0.85), (-1.55, 1.50), (0.35, 1.50), (1.05, 0.85)].map(CGPoint.init),
                    roofX: -0.6, roofLength: 1.9, roofY: 1.50, wheelRadius: 0.32, axle: 1.25, width: 1.75, length: 4.0)
        case .suv:
            Profile(hull: [(-2.35, 0.35), (-2.35, 1.0), (1.5, 1.0), (2.35, 0.75), (2.35, 0.35)].map(CGPoint.init),
                    cabin: [(-2.3, 1.0), (-2.2, 1.78), (0.6, 1.78), (1.35, 1.0)].map(CGPoint.init),
                    roofX: -0.8, roofLength: 2.7, roofY: 1.78, wheelRadius: 0.42, axle: 1.5, width: 1.95, length: 4.7)
        case .pickup:
            Profile(hull: [(-2.7, 0.40), (-2.7, 1.0), (1.6, 1.0), (2.7, 0.8), (2.7, 0.40)].map(CGPoint.init),
                    cabin: [(-0.3, 1.0), (0.1, 1.78), (1.0, 1.78), (1.55, 1.0)].map(CGPoint.init),
                    roofX: 0.55, roofLength: 0.9, roofY: 1.78, wheelRadius: 0.44, axle: 1.75, width: 2.0, length: 5.4,
                    bed: (-1.55, 2.3, 1.0))
        case .van:
            Profile(hull: [(-2.45, 0.35), (-2.45, 1.1), (1.6, 1.1), (2.45, 0.8), (2.45, 0.35)].map(CGPoint.init),
                    cabin: [(-2.4, 1.1), (-2.4, 1.95), (0.9, 1.95), (1.6, 1.1)].map(CGPoint.init),
                    roofX: -0.75, roofLength: 3.2, roofY: 1.95, wheelRadius: 0.4, axle: 1.55, width: 1.95, length: 4.9)
        case .coupe:
            Profile(hull: [(-2.2, 0.26), (-2.2, 0.70), (-1.0, 0.80), (1.6, 0.72), (2.2, 0.48), (2.2, 0.26)].map(CGPoint.init),
                    cabin: [(-1.1, 0.80), (-0.35, 1.28), (0.5, 1.28), (1.1, 0.80)].map(CGPoint.init),
                    roofX: 0.05, roofLength: 0.85, roofY: 1.28, wheelRadius: 0.34, axle: 1.35, width: 1.85, length: 4.4)
        }
    }

    // MARK: Scene

    static func makeScene(for spec: CarSpec, platform: Bool = true) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.2

        if platform {
            let turntable = SCNNode()
            turntable.addChildNode(Self.platform())
            scene.rootNode.addChildNode(turntable)
        }

        let car = SCNNode()
        car.name = "car"
        if let data = spec.modelData, let imported = importedModel(data) {
            car.addChildNode(imported)
        } else if let id = spec.libraryModelID, let entry = CarModelLibrary.shared.entry(id: id),
                  let model = libraryModel(entry, colorHex: spec.colorHex) {
            car.addChildNode(model)
        } else {
            car.addChildNode(stylizedCar(spec))
        }
        car.eulerAngles.y = -0.6
        scene.rootNode.addChildNode(car)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1000
        key.light?.castsShadow = true
        key.light?.shadowRadius = 8
        key.light?.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.eulerAngles = SCNVector3(-0.9, 0.7, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 450
        scene.rootNode.addChildNode(fill)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 60
        camera.position = SCNVector3(7.4, 3.2, 8.6)
        let target = SCNNode()
        target.position = SCNVector3(0, 0.7, 0)
        scene.rootNode.addChildNode(target)
        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        camera.constraints = [look]
        scene.rootNode.addChildNode(camera)

        return scene
    }

    private static func platform() -> SCNNode {
        let node = SCNNode()
        let disc = SCNCylinder(radius: 3.4, height: 0.08)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.11, green: 0.14, blue: 0.12, alpha: 1)
        material.roughness.contents = 0.6
        material.metalness.contents = 0.2
        disc.firstMaterial = material
        let discNode = SCNNode(geometry: disc)
        discNode.position.y = -0.04
        node.addChildNode(discNode)

        let ring = SCNTorus(ringRadius: 3.4, pipeRadius: 0.025)
        let glow = SCNMaterial()
        glow.diffuse.contents = UIColor(red: 0.773, green: 0.98, blue: 0.357, alpha: 1)
        glow.emission.contents = UIColor(red: 0.773, green: 0.98, blue: 0.357, alpha: 1)
        glow.lightingModel = .constant
        ring.firstMaterial = glow
        node.addChildNode(SCNNode(geometry: ring))
        return node
    }

    /// Soft gradient used for reflections, so metallic paint reads as shiny instead of black.
    private static func environmentImage() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 0.95, alpha: 1), UIColor(red: 0.62, green: 0.74, blue: 0.78, alpha: 1),
                          UIColor(white: 0.5, alpha: 1), UIColor(white: 0.28, alpha: 1)].map(\.cgColor)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.35, 0.55, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.9).setFill()
            ctx.cgContext.fill(CGRect(x: 60, y: 40, width: 140, height: 14))
            ctx.cgContext.fill(CGRect(x: 330, y: 70, width: 120, height: 10))
        }
    }

    // MARK: Stylized car

    private static func stylizedCar(_ spec: CarSpec) -> SCNNode {
        let p = profile(for: spec.body)
        let paint = paintMaterial(Color_uiColor(hex: spec.colorHex))
        let glass = glassMaterial()
        let root = SCNNode()

        let hull = extrude(roundedPath(p.hull, radius: 0.09), depth: p.width, material: paint)
        root.addChildNode(hull)

        let cabin = extrude(roundedPath(p.cabin, radius: 0.12), depth: p.width * 0.86, material: glass)
        root.addChildNode(cabin)

        let roof = SCNBox(width: p.roofLength, height: 0.05, length: p.width * 0.88, chamferRadius: 0.02)
        roof.firstMaterial = paint
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(p.roofX, p.roofY + 0.015, 0)
        root.addChildNode(roofNode)

        if let bed = p.bed {
            let inset = SCNBox(width: bed.length, height: 0.05, length: p.width * 0.84, chamferRadius: 0.01)
            let dark = SCNMaterial()
            dark.diffuse.contents = UIColor(white: 0.06, alpha: 1)
            dark.roughness.contents = 0.8
            inset.firstMaterial = dark
            let node = SCNNode(geometry: inset)
            node.position = SCNVector3(bed.x, bed.y + 0.02, 0)
            root.addChildNode(node)
        }

        let front = p.length / 2
        for side: CGFloat in [-1, 1] {
            root.addChildNode(light(color: UIColor(white: 1, alpha: 1), emission: UIColor(white: 0.95, alpha: 1),
                                    at: SCNVector3(front - 0.02, p.hull.map(\.y).max()! - 0.22, side * p.width * 0.32)))
            root.addChildNode(light(color: UIColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1),
                                    emission: UIColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1),
                                    at: SCNVector3(-front + 0.02, p.hull[1].y - 0.12, side * p.width * 0.34)))
            let mirror = SCNBox(width: 0.12, height: 0.1, length: 0.16, chamferRadius: 0.03)
            mirror.firstMaterial = paint
            let mirrorNode = SCNNode(geometry: mirror)
            mirrorNode.position = SCNVector3(p.cabin[0].x + (p.cabin[3].x - p.cabin[0].x) * 0.92, p.roofY - 0.38, side * (p.width / 2 + 0.06))
            root.addChildNode(mirrorNode)
        }

        for x in [-p.axle, p.axle] {
            for side: CGFloat in [-1, 1] {
                let wheel = wheelNode(style: spec.wheels, radius: p.wheelRadius)
                wheel.position = SCNVector3(x, p.wheelRadius, side * (p.width / 2 - 0.05))
                root.addChildNode(wheel)
            }
        }
        return root
    }

    private static func extrude(_ path: UIBezierPath, depth: CGFloat, material: SCNMaterial) -> SCNNode {
        path.flatness = 0.02
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = 0.06
        shape.firstMaterial = material
        let node = SCNNode(geometry: shape)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation(0, 0, (minB.z + maxB.z) / 2)
        return node
    }

    /// Closed polygon with rounded corners, in side-view coordinates.
    private static func roundedPath(_ points: [CGPoint], radius: CGFloat) -> UIBezierPath {
        let path = CGMutablePath()
        let n = points.count
        path.move(to: CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2))
        for i in 1...n {
            path.addArc(tangent1End: points[i % n], tangent2End: points[(i + 1) % n], radius: radius)
        }
        path.closeSubpath()
        return UIBezierPath(cgPath: path)
    }

    private static func wheelNode(style: CarWheelStyle, radius: CGFloat) -> SCNNode {
        let node = SCNNode()
        let tireWidth: CGFloat = style == .offroad ? 0.34 : 0.26
        let tire = SCNCylinder(radius: radius, height: tireWidth)
        let rubber = SCNMaterial()
        rubber.lightingModel = .physicallyBased
        rubber.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        rubber.roughness.contents = 0.9
        tire.firstMaterial = rubber
        let tireNode = SCNNode(geometry: tire)
        tireNode.eulerAngles.x = .pi / 2
        node.addChildNode(tireNode)

        let rimMaterial = SCNMaterial()
        rimMaterial.lightingModel = .physicallyBased
        rimMaterial.metalness.contents = 1.0
        rimMaterial.roughness.contents = 0.25
        rimMaterial.diffuse.contents = style == .offroad ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.82, alpha: 1)

        let rimRadius = radius * (style == .offroad ? 0.5 : 0.68)
        let rim = SCNCylinder(radius: rimRadius, height: tireWidth + 0.02)
        rim.firstMaterial = rimMaterial
        let rimNode = SCNNode(geometry: rim)
        rimNode.eulerAngles.x = .pi / 2
        node.addChildNode(rimNode)

        if style == .sport {
            let dark = SCNMaterial()
            dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
            let hub = SCNCylinder(radius: rimRadius * 0.82, height: tireWidth + 0.03)
            hub.firstMaterial = dark
            let hubNode = SCNNode(geometry: hub)
            hubNode.eulerAngles.x = .pi / 2
            node.addChildNode(hubNode)
            for i in 0..<5 {
                let spoke = SCNBox(width: rimRadius * 1.55, height: 0.05, length: 0.06, chamferRadius: 0.01)
                spoke.firstMaterial = rimMaterial
                let spokeNode = SCNNode(geometry: spoke)
                spokeNode.position.z = Float((tireWidth + 0.04) / 2)
                spokeNode.eulerAngles.z = Float(i) * .pi / 5
                node.addChildNode(spokeNode)
                let back = spokeNode.clone()
                back.position.z = -Float((tireWidth + 0.04) / 2)
                node.addChildNode(back)
            }
        }
        return node
    }

    private static func light(color: UIColor, emission: UIColor, at position: SCNVector3) -> SCNNode {
        let box = SCNBox(width: 0.06, height: 0.12, length: 0.3, chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = emission
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.position = position
        return node
    }

    private static func paintMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = 0.2
        material.roughness.contents = 0.32
        return material
    }

    private static func glassMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.10, green: 0.17, blue: 0.22, alpha: 1)
        material.metalness.contents = 0.5
        material.roughness.contents = 0.12
        return material
    }

    private static func Color_uiColor(hex: String) -> UIColor {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    // MARK: Imported and library models

    /// Loads a user-supplied .usdz, scaled to car size and sitting on the platform.
    private static func importedModel(_ data: Data) -> SCNNode? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lot-car-\(data.count).usdz")
        do {
            try data.write(to: url)
            return try loadNormalized(url: url)
        } catch {
            return nil
        }
    }

    /// Loads a model from the library and, for palette-textured models, repaints the body in the car's color.
    private static func libraryModel(_ entry: CarModelEntry, colorHex: String) -> SCNNode? {
        let library = CarModelLibrary.shared
        guard let url = library.localURL(for: entry), let node = try? loadNormalized(url: url) else { return nil }
        if let tinted = library.recoloredPalette(for: entry, colorHex: colorHex) {
            node.enumerateHierarchy { child, _ in
                for material in child.geometry?.materials ?? [] {
                    material.diffuse.contents = tinted
                    material.lightingModel = .physicallyBased
                    material.roughness.contents = 0.5
                    material.metalness.contents = 0.05
                }
            }
        }
        return node
    }

    private static func loadNormalized(url: URL) throws -> SCNNode {
        let scene = try SCNScene(url: url, options: nil)
        let container = SCNNode()
        for child in scene.rootNode.childNodes { container.addChildNode(child) }
        let (minB, maxB) = container.boundingBox
        let size = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        let longest = max(size.x, size.z, 0.001)
        let scale = 4.0 / longest
        container.scale = SCNVector3(scale, scale, scale)
        container.position = SCNVector3(-(minB.x + maxB.x) / 2 * scale, -minB.y * scale, -(minB.z + maxB.z) / 2 * scale)
        let wrapper = SCNNode()
        wrapper.addChildNode(container)
        // Put the long axis along x, like the stylized car.
        if size.z > size.x { wrapper.eulerAngles.y = .pi / 2 }
        return wrapper
    }
}
