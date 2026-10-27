import SwiftUI

extension CarBodyStyle {
    /// Typical overall height in meters, used to size the car against the garage.
    var realHeightMeters: CGFloat {
        switch self {
        case .sedan: 1.45
        case .hatchback: 1.50
        case .coupe: 1.30
        case .suv: 1.70
        case .pickup: 1.90
        case .van: 1.95
        }
    }
}

/// How the user has placed the car in the garage: moved anywhere, and resized, independently, like a photo.
struct GarageAdjustment: Equatable {
    /// Shift as a fraction of the scene's width and height.
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    /// Size multiplier. 1 is the default size.
    var scale: CGFloat = 1

    static let neutral = GarageAdjustment()
    static let scaleRange: ClosedRange<CGFloat> = 0.4...2.0

    var isNeutral: Bool { abs(offsetX) < 0.002 && abs(offsetY) < 0.002 && abs(scale - 1) < 0.002 }

    init(offsetX: CGFloat = 0, offsetY: CGFloat = 0, scale: CGFloat = 1) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    init(car: Car) {
        self.init(offsetX: CGFloat(car.garageOffsetX), offsetY: CGFloat(car.garageOffsetY), scale: CGFloat(car.garageScale))
    }
}

extension Car {
    var garageAdjustment: GarageAdjustment {
        get { GarageAdjustment(car: self) }
        set { garageOffsetX = Double(newValue.offsetX); garageOffsetY = Double(newValue.offsetY); garageScale = Double(newValue.scale) }
    }
}

/// Works out where everything goes so the car and the room agree with each other.
///
/// The scale comes from the car: its real height (by body type) fixes pixels-per-meter at the parking spot. From that the
/// room is derived with ordinary perspective: the horizon sits at camera height above the car's ground line, the back wall is
/// farther away (so smaller), and the door, ceiling and side walls use real garage dimensions. The car's tires are then placed
/// on the floor exactly where the analysis found them.
struct GarageLayout {
    static let eyeHeight: CGFloat = 1.05
    static let ceilingHeight: CGFloat = 2.8
    static let doorHeight: CGFloat = 2.1
    static let doorWidth: CGFloat = 4.8       // a standard two-car door
    static let wallDepthRatio: CGFloat = 1.45   // the back wall is this much farther from the camera than the car
    static let groundFraction: CGFloat = 0.78   // where the car's lowest tire sits, as a fraction of the height
    static let preferredScale: CGFloat = 0.215   // pixels per meter at the car, as a fraction of the height

    let size: CGSize
    let centerX: CGFloat
    let horizonY: CGFloat
    /// Pixels per meter at the car's depth, and at the back wall's depth.
    let carScale: CGFloat
    let wallScale: CGFloat
    let wall: CGRect
    let door: CGRect
    /// The car's frame (its cropped image), or nil when there is no car yet.
    let carFrame: CGRect?
    let groundY: CGFloat
    /// The lowest tire contact in scene coordinates, and its flat width.
    let contacts: [CGPoint]
    let contactWidths: [CGFloat]
    /// The span of the car's underside along the floor, in scene x coordinates.
    let footprint: ClosedRange<CGFloat>?

    /// Where the light falls: the middle of the car's underside.
    var carCenterX: CGFloat {
        if let footprint { return (footprint.lowerBound + footprint.upperBound) / 2 }
        return carFrame.map { $0.midX } ?? centerX
    }

    /// The adjustment after limits were applied, so the UI can show what actually happened.
    let appliedAdjustment: GarageAdjustment

    init(size: CGSize, analysis: VehicleAnalysis?, bodyHeight: CGFloat, adjustment: GarageAdjustment = .neutral) {
        self.size = size
        let w = size.width, h = size.height
        centerX = w / 2
        let defaultGround = h * Self.groundFraction

        var scale = h * Self.preferredScale
        var aspect: CGFloat = 1.6
        if let analysis {
            aspect = analysis.image.size.width / max(analysis.image.size.height, 1)
            scale = min(scale, w * 0.9 / (aspect * bodyHeight))
        }
        let baseScale = scale

        // The room is fixed by the default car, and doesn't move when the user moves the car.
        horizonY = defaultGround - Self.eyeHeight * baseScale
        wallScale = baseScale / Self.wallDepthRatio
        let wallBottom = horizonY + Self.eyeHeight * wallScale
        let wallTop = horizonY - (Self.ceilingHeight - Self.eyeHeight) * wallScale
        let top = min(wallTop, 0)
        wall = CGRect(x: 0, y: top, width: w, height: wallBottom - top)
        let doorWidth = min(Self.doorWidth * wallScale, w * 0.96)
        door = CGRect(x: (w - doorWidth) / 2, y: wallBottom - Self.doorHeight * wallScale, width: doorWidth, height: Self.doorHeight * wallScale)

        var frame: CGRect?
        var contactPoints: [CGPoint] = [], widths: [CGFloat] = []
        var span: ClosedRange<CGFloat>?
        var applied = GarageAdjustment.neutral
        var ground = defaultGround
        var appliedScale = baseScale

        if let analysis {
            let baseH = bodyHeight * baseScale, baseW = baseH * aspect
            let balance = 0.5 * 0.5 + CGFloat(analysis.geometry.footprintCenterX) * 0.5
            let baseRect = CGRect(x: w / 2 - balance * baseW, y: defaultGround - baseH, width: baseW, height: baseH)

            // The user's change is applied like it would be to a photo: resize about its middle, then move.
            let multiplier = min(max(adjustment.scale, GarageAdjustment.scaleRange.lowerBound), GarageAdjustment.scaleRange.upperBound)
            let carH = baseH * multiplier, carW = baseW * multiplier
            var rect = CGRect(x: baseRect.midX + adjustment.offsetX * w - carW / 2,
                              y: baseRect.midY + adjustment.offsetY * h - carH / 2, width: carW, height: carH)
            // Keep most of the car in the picture however hard it's dragged.
            rect.origin.x = min(max(rect.origin.x, -carW * 0.3), w - carW * 0.7)
            rect.origin.y = min(max(rect.origin.y, -carH * 0.45), h - carH * 0.55)

            frame = rect
            ground = rect.maxY
            appliedScale = baseScale * multiplier
            applied = GarageAdjustment(offsetX: (rect.midX - baseRect.midX) / w, offsetY: (rect.midY - baseRect.midY) / h, scale: multiplier)
            // The image's bottom edge is its lowest tire. Put every contact on that scale.
            contactPoints = analysis.geometry.contacts.map { CGPoint(x: rect.minX + CGFloat($0.x) * carW, y: rect.minY + CGFloat($0.y) * carH) }
            widths = analysis.geometry.contacts.map { CGFloat($0.width) * carW }
            span = (rect.minX + CGFloat(analysis.geometry.footprint.lowerBound) * carW)...(rect.minX + CGFloat(analysis.geometry.footprint.upperBound) * carW)
        }
        carFrame = frame
        groundY = ground
        carScale = appliedScale
        contacts = contactPoints
        contactWidths = widths
        footprint = span
        appliedAdjustment = applied
    }

    /// Extends the line from the vanishing point through `point` until it reaches `y`.
    func extend(through point: CGPoint, toY y: CGFloat) -> CGPoint {
        let vp = CGPoint(x: centerX, y: horizonY)
        let dy = point.y - vp.y
        guard abs(dy) > 0.001 else { return point }
        let t = (y - vp.y) / dy
        return CGPoint(x: vp.x + (point.x - vp.x) * t, y: y)
    }

    /// Extends the line from the vanishing point through `point` until it reaches `x`.
    func extend(through point: CGPoint, toX x: CGFloat) -> CGPoint {
        let vp = CGPoint(x: centerX, y: horizonY)
        let dx = point.x - vp.x
        guard abs(dx) > 0.001 else { return point }
        let t = (x - vp.x) / dx
        return CGPoint(x: x, y: vp.y + (point.y - vp.y) * t)
    }
}
