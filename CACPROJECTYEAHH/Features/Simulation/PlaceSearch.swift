import SwiftUI
import MapKit

/// A place picked for a simulated drive.
struct SimPlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let item: MKMapItem

    static func == (a: SimPlace, b: SimPlace) -> Bool { a.id == b.id }
}

enum RouteError: LocalizedError {
    case noRoute

    var errorDescription: String? { "Couldn't find a driving route between those two places." }
}

/// Finds a driving route between two places with Apple Maps. The route follows real roads.
enum RouteFinder {
    struct Result {
        let points: [RoutePoint]
        let distance: CLLocationDistance
        let expectedTravelTime: TimeInterval
    }

    static func driving(from: MKMapItem, to: MKMapItem) async throws -> Result {
        let request = MKDirections.Request()
        request.source = from
        request.destination = to
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RouteError.noRoute }
        let polyline = route.polyline
        var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return Result(points: coordinates.map { RoutePoint(lat: $0.latitude, lon: $0.longitude) },
                      distance: route.distance, expectedTravelTime: route.expectedTravelTime)
    }

    /// Resolves a typed place name (for example "Iowa State University") to a map item.
    static func resolve(_ text: String) async -> SimPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return SimPlace(name: item.name ?? text, subtitle: item.placemark.title ?? "", item: item)
    }
}

/// Live place suggestions as the user types.
@Observable
final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" { didSet { completer.queryFragment = query } }
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }

    func place(for completion: MKLocalSearchCompletion) async -> SimPlace? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else { return nil }
        return SimPlace(name: completion.title.isEmpty ? (item.name ?? "Place") : completion.title, subtitle: completion.subtitle, item: item)
    }
}

/// Type to search, tap to choose.
struct PlaceSearchSheet: View {
    let title: String
    let onPick: (SimPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = PlaceSearchModel()
    @State private var resolving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                Spacer()
                Text(title).font(LotType.title).foregroundStyle(Lot.warmWhite)
                Spacer()
                Color.clear.frame(width: 60, height: 44)
            }
            .padding(.horizontal, Lot.Space.gutter)
            .padding(.top, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Lot.muted)
                TextField("", text: $model.query, prompt: Text("Search a place or address").foregroundStyle(Lot.muted))
                    .focused($focused)
                    .foregroundStyle(Lot.warmWhite)
                    .autocorrectionDisabled()
                if resolving { ProgressView().tint(Lot.warmWhite) }
            }
            .padding(.horizontal, 16).frame(height: 50)
            .background(Capsule().fill(Lot.charcoalRaised))
            .padding(Lot.Space.gutter)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button { pick(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title).font(LotType.body.weight(.medium)).foregroundStyle(Lot.warmWhite)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle).font(LotType.caption).foregroundStyle(Lot.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, Lot.Space.gutter)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Lot.hairline)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lotScreen()
        .onAppear { focused = true }
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        resolving = true
        Task {
            if let place = await model.place(for: suggestion) {
                onPick(place)
                dismiss()
            }
            resolving = false
        }
    }
}
