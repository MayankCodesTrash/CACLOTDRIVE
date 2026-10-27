import SwiftUI

/// A dark studio garage with the car parked in it. Pure 2D layers, and the car is a flat picture, so it doesn't rotate.
///
/// The car is measured first (`VehicleGeometryAnalyzer`), and `GarageLayout` sizes it by its real height and builds the room
/// around it in matching perspective, so the tires sit on the floor, the shadow sits under the actual wheels, and the garage
/// door is the right size next to the car.
struct GarageSceneView: View {
    let vehicle: UIImage?
    /// False when the photo still has its own background. It's then shown as a framed picture standing on the floor.
    var isCutout = true
    var bodyStyle: CarBodyStyle = .sedan
    /// Where the user has parked the car. The default is the centered spot.
    var adjustment: GarageAdjustment = .neutral
    /// Draws a dashed outline around the car while the user is moving it.
    var showsAdjustOutline = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let analysis = isCutout ? vehicle.flatMap(VehicleGeometryAnalyzer.cachedAnalysis(of:)) : nil
            let layout = GarageLayout(size: size, analysis: analysis, bodyHeight: bodyStyle.realHeightMeters, adjustment: adjustment)

            ZStack(alignment: .topLeading) {
                GarageBackdrop(layout: layout)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                if let vehicle {
                    if isCutout, let analysis {
                        CarLayer(analysis: analysis, layout: layout)
                            .frame(width: size.width, height: size.height, alignment: .topLeading)
                    } else if !isCutout {
                        PhotoPlateLayer(image: vehicle, size: size, groundY: layout.groundY)
                            .frame(width: size.width, height: size.height, alignment: .topLeading)
                    }
                }
                if showsAdjustOutline, let frame = layout.carFrame { AdjustOutline(frame: frame) }
                #if DEBUG
                if CommandLine.arguments.contains("-garageGuides") { GarageGuides(layout: layout) }
                #endif
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Room

/// A straight-on view into a studio garage: a back wall with a big sectional door framed in lime LED light, a polished floor
/// that fades into the distance with a soft reflection, and a glow behind the parking spot so the car stands out from the wall.
private struct GarageBackdrop: View {
    let layout: GarageLayout
    private let lime = Lot.lime

    var body: some View {
        ZStack {
            Canvas { ctx, size in draw(&ctx, size) }
            RadialGradient(colors: [.clear, .black.opacity(0.5)],
                           center: .init(x: layout.carCenterX / max(layout.size.width, 1), y: 0.6),
                           startRadius: layout.size.width * 0.4, endRadius: layout.size.width * 0.98)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        drawWall(&ctx)
        drawDoor(&ctx)
        drawFloor(&ctx)
        drawLights(&ctx)
        drawGrain(&ctx, size)
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path { Path { $0.move(to: a); $0.addLine(to: b) } }

    private func glowStroke(_ ctx: inout GraphicsContext, _ path: Path, width: CGFloat, glow: CGFloat = 8, opacity: Double = 0.8) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: glow))
            layer.stroke(path, with: .color(lime.opacity(opacity)), lineWidth: width * 3)
        }
        ctx.stroke(path, with: .color(lime), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // MARK: Wall

    private func drawWall(_ ctx: inout GraphicsContext) {
        let w = layout.size.width, wall = layout.wall
        ctx.fill(Path(wall), with: .linearGradient(Gradient(colors: [Color(hex: 0x070A09), Color(hex: 0x131B18), Color(hex: 0x1A2420)]),
                                                   startPoint: .init(x: 0, y: wall.minY), endPoint: .init(x: 0, y: wall.maxY)))

        let panel = 0.6 * layout.wallScale
        var index = -Int(w / panel) - 1
        while CGFloat(index) * panel + layout.centerX < w + panel {
            let x = layout.centerX + CGFloat(index) * panel
            ctx.fill(Path(CGRect(x: x, y: wall.minY, width: panel, height: wall.height)), with: .color(.white.opacity(index % 2 == 0 ? 0.022 : 0.006)))
            ctx.fill(Path(CGRect(x: x, y: wall.minY, width: 1, height: wall.height)), with: .color(.black.opacity(0.4)))
            index += 1
        }
        let rail = layout.horizonY + (GarageLayout.eyeHeight - 1.0) * layout.wallScale
        ctx.stroke(line(.init(x: 0, y: rail), .init(x: w, y: rail)), with: .color(.white.opacity(0.07)), lineWidth: 1)

        // The wall brightens behind the car, which separates the silhouette from it.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.translateBy(x: layout.carCenterX, y: layout.groundY - layout.carScale * 0.9)
            layer.scaleBy(x: 1.5, y: 1)
            layer.fill(Path(CGRect(x: -w, y: -w, width: w * 2, height: w * 2)),
                       with: .radialGradient(Gradient(colors: [lime.opacity(0.17), .white.opacity(0.07), .clear]),
                                             center: .zero, startRadius: 0, endRadius: layout.carScale * 2.6))
        }
    }

    private func drawDoor(_ ctx: inout GraphicsContext) {
        let door = layout.door
        let panels = 5
        let panelHeight = door.height / CGFloat(panels)
        for i in 0..<panels {
            let rect = CGRect(x: door.minX, y: door.minY + CGFloat(i) * panelHeight, width: door.width, height: panelHeight)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(hex: i % 2 == 0 ? 0x2A3531 : 0x25302C), Color(hex: 0x161E1B)]),
                startPoint: rect.origin, endPoint: .init(x: rect.minX, y: rect.maxY)))
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1.2)), with: .color(.white.opacity(0.12)))
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.maxY - 1.5, width: rect.width, height: 1.5)), with: .color(.black.opacity(0.55)))
            ctx.fill(Path(CGRect(x: rect.minX + 6, y: rect.midY, width: rect.width - 12, height: 1)), with: .color(.white.opacity(0.05)))
        }
        let windows = 8
        let gap = door.width * 0.016
        let windowWidth = (door.width - gap * CGFloat(windows + 1)) / CGFloat(windows)
        for i in 0..<windows {
            let rect = CGRect(x: door.minX + gap + CGFloat(i) * (windowWidth + gap), y: door.minY + panelHeight * 0.3,
                              width: windowWidth, height: panelHeight * 0.4)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x6F8F80).opacity(0.5), Color(hex: 0x24342E).opacity(0.7)]),
                startPoint: rect.origin, endPoint: .init(x: rect.minX, y: rect.maxY)))
        }
        ctx.stroke(Path(door), with: .color(.black.opacity(0.7)), lineWidth: 2)

        let inset: CGFloat = 0.1 * layout.wallScale
        let frame = door.insetBy(dx: -inset, dy: -inset)
        var path = Path()
        path.move(to: .init(x: frame.minX, y: frame.maxY))
        path.addLine(to: .init(x: frame.minX, y: frame.minY))
        path.addLine(to: .init(x: frame.maxX, y: frame.minY))
        path.addLine(to: .init(x: frame.maxX, y: frame.maxY))
        glowStroke(&ctx, path, width: 2.4, glow: 9)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 26))
            layer.stroke(path, with: .color(lime.opacity(0.22)), lineWidth: 22)
        }
    }

    // MARK: Floor

    private func drawFloor(_ ctx: inout GraphicsContext) {
        let w = layout.size.width, h = layout.size.height, wall = layout.wall
        let top = wall.maxY
        let floor = CGRect(x: 0, y: top, width: w, height: h - top)
        ctx.fill(Path(floor), with: .linearGradient(Gradient(colors: [Color(hex: 0x2B3732), Color(hex: 0x131A17), Color(hex: 0x070A09)]),
                                                    startPoint: .init(x: 0, y: top), endPoint: .init(x: 0, y: h)))

        for i in -14...14 {
            let far = CGPoint(x: layout.centerX + CGFloat(i) * 0.6 * layout.wallScale, y: top)
            ctx.stroke(line(far, layout.extend(through: far, toY: h)), with: .color(.white.opacity(0.045)), lineWidth: 1)
        }
        let wallDistance: CGFloat = 5.5
        var depth = wallDistance
        while depth > 1.2 {
            let scale = layout.wallScale * wallDistance / depth
            let y = layout.horizonY + GarageLayout.eyeHeight * scale
            if y > top, y < h { ctx.stroke(line(.init(x: 0, y: y), .init(x: w, y: y)), with: .color(.white.opacity(0.04)), lineWidth: 1) }
            depth -= 0.6
        }

        // The door's light and the LED frame reflect in the polished floor, fading with distance.
        let door = layout.door
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.fill(Path(CGRect(x: door.minX, y: top, width: door.width, height: layout.size.height * 0.1)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .clear]), startPoint: .init(x: 0, y: top), endPoint: .init(x: 0, y: top + layout.size.height * 0.1)))
            for x in [door.minX, door.maxX] {
                layer.fill(Path(CGRect(x: x - 5, y: top, width: 10, height: layout.size.height * 0.16)),
                           with: .linearGradient(Gradient(colors: [lime.opacity(0.35), .clear]), startPoint: .init(x: 0, y: top), endPoint: .init(x: 0, y: top + layout.size.height * 0.16)))
            }
        }

        glowStroke(&ctx, line(.init(x: 0, y: top), .init(x: w, y: top)), width: 1.4, glow: 5, opacity: 0.5)

        // A pool of light on the parking spot, squashed into an ellipse by scaling the layer so it fades without a hard edge.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.translateBy(x: layout.carCenterX, y: layout.groundY)
            layer.scaleBy(x: 1, y: 0.36)
            layer.fill(Path(CGRect(x: -w, y: -w, width: w * 2, height: w * 2)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.07), .clear]),
                                             center: .zero, startRadius: 0, endRadius: w * 0.5))
        }
    }

    // MARK: Light

    private func drawLights(_ ctx: inout GraphicsContext) {
        let w = layout.size.width, bottom = layout.groundY
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 18))
            for offset in [-0.2, 0, 0.2] as [CGFloat] {
                let x = layout.carCenterX + w * offset
                let cone = Path { p in
                    p.move(to: .init(x: x - w * 0.015, y: 0)); p.addLine(to: .init(x: x + w * 0.015, y: 0))
                    p.addLine(to: .init(x: x + w * 0.13, y: bottom)); p.addLine(to: .init(x: x - w * 0.13, y: bottom))
                    p.closeSubpath()
                }
                layer.fill(cone, with: .linearGradient(Gradient(colors: [.white.opacity(offset == 0 ? 0.11 : 0.07), .clear]),
                                                       startPoint: .init(x: x, y: 0), endPoint: .init(x: x, y: bottom)))
            }
        }
    }

    /// Fine, fixed film grain so the gradients don't look flat or banded.
    private func drawGrain(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / 65535
        }
        let count = Int(sz.width * sz.height / 90)
        for _ in 0..<count {
            let rect = CGRect(x: next() * sz.width, y: next() * sz.height, width: 1.2, height: 1.2)
            ctx.fill(Path(rect), with: .color((next() > 0.5 ? Color.white : Color.black).opacity(0.045)))
        }
    }
}

// MARK: - Car

/// The measured cutout: reflection, a shadow under the actual tires, then the car.
private struct CarLayer: View {
    let analysis: VehicleAnalysis
    let layout: GarageLayout

    var body: some View {
        if let rect = layout.carFrame {
            let image = analysis.image
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.9), location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 1, y: -1)
                    .frame(width: rect.width, height: rect.height)
                    .opacity(0.26)
                    .blur(radius: 1.5)
                    .position(x: rect.midX, y: rect.maxY + rect.height / 2 + 3)

                shadows(rect)

                Image(uiImage: image).resizable()
                    .frame(width: rect.width, height: rect.height)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// A soft shadow under the whole underside of the car, plus a tight dark patch right where the lowest tire meets the floor.
    @ViewBuilder
    private func shadows(_ rect: CGRect) -> some View {
        let span = layout.footprint ?? rect.minX...rect.maxX
        // The far side of the car sits a little higher in the picture, so the middle of its shadow sits a little above the lowest tire.
        let center = CGPoint(x: (span.lowerBound + span.upperBound) / 2, y: rect.maxY - rect.height * 0.03)

        Ellipse().fill(.black.opacity(0.82))
            .frame(width: (span.upperBound - span.lowerBound) + rect.width * 0.1, height: max(14, rect.height * 0.19))
            .blur(radius: 9)
            .position(center)
        ForEach(Array(layout.contacts.enumerated()), id: \.offset) { index, point in
            Ellipse().fill(.black.opacity(0.95))
                .frame(width: max(layout.contactWidths[index] * 1.8, rect.width * 0.1), height: max(6, rect.height * 0.055))
                .blur(radius: 3.5)
                .position(x: point.x, y: point.y - 1)
        }
    }
}

/// A photo with its background still in it: a framed picture standing on the garage floor, with shadow and reflection.
private struct PhotoPlateLayer: View {
    let image: UIImage
    let size: CGSize
    let groundY: CGFloat

    var body: some View {
        let aspect = image.size.width / max(image.size.height, 1)
        let maxWidth = size.width * 0.84
        let maxHeight = size.height * 0.5
        let width = min(maxWidth, maxHeight * aspect)
        let height = width / aspect
        let centerX = size.width / 2

        ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: width, height: height).clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: .black.opacity(0.9), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: 1, y: -1)
                .opacity(0.2)
                .blur(radius: 1.5)
                .position(x: centerX, y: groundY + height / 2 + 3)

            Ellipse().fill(.black.opacity(0.7))
                .frame(width: width * 0.96, height: max(12, size.height * 0.045))
                .blur(radius: 10)
                .position(x: centerX, y: groundY)

            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: Lot.lime.opacity(0.12), radius: 16, y: -2)
                .position(x: centerX, y: groundY - height / 2)
        }
    }
}

#if DEBUG
/// Debug overlay (`-garageGuides`): shows what was measured, so alignment can be checked by eye.
private struct GarageGuides: View {
    let layout: GarageLayout

    var body: some View {
        Canvas { ctx, size in
            func hline(_ y: CGFloat, _ color: Color) {
                ctx.stroke(Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) },
                           with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            hline(layout.horizonY, .yellow)
            hline(layout.groundY, .cyan)
            ctx.stroke(Path(layout.wall), with: .color(.pink), lineWidth: 1)
            if let car = layout.carFrame { ctx.stroke(Path(car), with: .color(.green), lineWidth: 1) }
            for point in layout.contacts {
                ctx.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(.red))
            }
            if let span = layout.footprint {
                ctx.stroke(Path { $0.move(to: .init(x: span.lowerBound, y: layout.groundY + 6)); $0.addLine(to: .init(x: span.upperBound, y: layout.groundY + 6)) },
                           with: .color(.orange), lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif

/// Dashed frame and handles around the car while it is being moved.
private struct AdjustOutline: View {
    let frame: CGRect

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Lot.lime.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .frame(width: frame.width + 10, height: frame.height + 10)
                .position(x: frame.midX, y: frame.midY)
            ForEach(Array([CGPoint(x: frame.minX - 5, y: frame.minY - 5), CGPoint(x: frame.maxX + 5, y: frame.minY - 5),
                           CGPoint(x: frame.minX - 5, y: frame.maxY + 5), CGPoint(x: frame.maxX + 5, y: frame.maxY + 5)].enumerated()), id: \.offset) { _, point in
                Circle().fill(Lot.lime).frame(width: 9, height: 9).position(point)
            }
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Lot.charcoal)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Lot.lime))
                .position(x: frame.midX, y: frame.midY)
        }
        .allowsHitTesting(false)
    }
}
