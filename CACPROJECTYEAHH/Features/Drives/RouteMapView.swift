import SwiftUI
import MapKit

/// The route line and its start and end dots, shared by the preview map and the full-screen map.
struct RouteMapContent: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        // A light outline under the lime line keeps it readable on top of the street grid.
        MapPolyline(coordinates: coordinates)
            .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        MapPolyline(coordinates: coordinates)
            .stroke(Lot.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        if let start = coordinates.first {
            Annotation("Start", coordinate: start, anchor: .center) {
                Circle().fill(Lot.warmWhite).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Lot.charcoal, lineWidth: 3))
            }
        }
        if let end = coordinates.last, coordinates.count > 1 {
            Annotation("End", coordinate: end, anchor: .center) {
                Circle().fill(Lot.lime).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Lot.warmWhite, lineWidth: 3))
            }
        }
    }
}

/// A real map with the recorded route drawn on it, framed to fit the whole route. Tap it to explore.
struct RouteMapView: View {
    let points: [RoutePoint]
    var isSample = false

    var body: some View {
        let coordinates = points.map(\.coordinate)
        Map(initialPosition: .rect(Self.fittingRect(for: coordinates)), interactionModes: []) {
            RouteMapContent(coordinates: coordinates)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topLeading) {
            if isSample && SampleLabels.isVisible { LotChip(text: "Sample route").padding(12) }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Lot.warmWhite)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Lot.charcoal.opacity(0.7)))
                .padding(12)
        }
        .accessibilityLabel(isSample ? "Map of a sample route" : "Map of your route")
        .accessibilityHint("Opens a full-screen map you can pan and zoom")
        .accessibilityAddTraits(.isButton)
    }

    /// A map rectangle around the route, with margin so the line isn't against the edge.
    static func fittingRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard let first = coordinates.first else { return .world }
        let mapPoints = coordinates.map(MKMapPoint.init)
        var minX = mapPoints[0].x, maxX = minX, minY = mapPoints[0].y, maxY = minY
        for p in mapPoints { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }

        // Never zoom in tighter than about 600 m, so a very short trip still shows some surroundings.
        let minSpan = MKMapPointsPerMeterAtLatitude(first.latitude) * 600
        var width = max(maxX - minX, minSpan), height = max(maxY - minY, minSpan)
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        width *= 1.3; height *= 1.3
        return MKMapRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }
}

/// Full-screen, explorable map of a drive: pan, zoom, rotate, see street names, switch to satellite, jump back to the route.
struct RouteMapScreen: View {
    let title: String
    let subtitle: String
    let points: [RoutePoint]
    var isSample = false

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var satellite = false

    init(title: String, subtitle: String, points: [RoutePoint], isSample: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.points = points
        self.isSample = isSample
        _position = State(initialValue: .rect(RouteMapView.fittingRect(for: points.map(\.coordinate))))
    }

    var body: some View {
        let coordinates = points.map(\.coordinate)
        Map(position: $position) {
            RouteMapContent(coordinates: coordinates)
        }
        .mapStyle(satellite
                  ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
                  : .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottomTrailing) { controls }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            LotCircleButton(symbol: "xmark", label: "Close map") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LotType.title).foregroundStyle(Lot.warmWhite).lineLimit(1)
                HStack(spacing: 8) {
                    Text(subtitle).font(LotType.labelSmall).foregroundStyle(Lot.warmWhite.opacity(0.8))
                    if isSample && SampleLabels.isVisible { LotChip(text: "Sample route") }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoal.opacity(0.7)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Lot.Space.gutter)
        .padding(.top, 8)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            LotCircleButton(symbol: satellite ? "map" : "globe.americas", label: satellite ? "Show street map" : "Show satellite") {
                withAnimation { satellite.toggle() }
            }
            LotCircleButton(symbol: "location.viewfinder", label: "Show the whole route") {
                withAnimation(.smooth) { position = .rect(RouteMapView.fittingRect(for: points.map(\.coordinate))) }
            }
        }
        .padding(.trailing, Lot.Space.gutter)
        .padding(.bottom, 40)
    }
}
