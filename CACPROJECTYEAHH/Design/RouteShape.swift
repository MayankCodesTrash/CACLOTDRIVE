import SwiftUI
import CoreLocation

struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum RouteGeometry {
    /// Maps a lat/lon polyline into the unit square, keeping its true aspect ratio and centering it.
    static func normalized(_ points: [RoutePoint]) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let meanLat = points.map(\.lat).reduce(0, +) / Double(points.count)
        let xs = points.map { $0.lon * cos(meanLat * .pi / 180) }
        let ys = points.map { -$0.lat }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY, 1e-9)
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        return zip(xs, ys).map { CGPoint(x: ($0 - minX + offsetX) / span, y: ($1 - minY + offsetY) / span) }
    }
}

/// A recorded route drawn as a plain path. Works inside ImageRenderer, unlike MapKit views.
struct RouteShape: Shape {
    let points: [RoutePoint]

    func path(in rect: CGRect) -> Path {
        let unit = RouteGeometry.normalized(points)
        guard let first = unit.first else { return Path() }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }
        var path = Path()
        path.move(to: map(first))
        for point in unit.dropFirst() { path.addLine(to: map(point)) }
        return path
    }

    func endpoints(in rect: CGRect) -> (start: CGPoint, end: CGPoint)? {
        let unit = RouteGeometry.normalized(points)
        guard let first = unit.first, let last = unit.last else { return nil }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }
        return (map(first), map(last))
    }
}

/// Route line with start and end markers.
struct RouteLine: View {
    let points: [RoutePoint]
    var color: Color = Lot.lime
    var lineWidth: CGFloat = 4
    var markerColor: Color = Lot.warmWhite

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let shape = RouteShape(points: points)
            ZStack {
                shape.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let ends = shape.endpoints(in: rect) {
                    Circle().fill(markerColor).frame(width: lineWidth * 2.4, height: lineWidth * 2.4).position(ends.start)
                    Circle().fill(color).frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
                        .overlay(Circle().stroke(markerColor, lineWidth: lineWidth * 0.6))
                        .position(ends.end)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
