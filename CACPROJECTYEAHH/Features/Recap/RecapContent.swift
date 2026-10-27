import SwiftUI

enum RecapStyle: String, CaseIterable, Identifiable {
    case night, photoDump, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: "Night Drive"
        case .photoDump: "Photo Dump"
        case .minimal: "Minimal"
        }
    }
}

/// Everything a recap card shows. Built only from saved trip data and what the user typed.
struct RecapContent {
    var title: String
    var dateText: String
    var durationText: String?
    var distanceText: String?
    var carText: String?
    var caption: String
    var photos: [UIImage]
    var route: [RoutePoint]
    var scene: SceneStyle
    var sceneSeed: Int
    var isSample: Bool

    /// `photoOverride` replaces the trip's own photos when the user picks a different image.
    init(trip: Drive, photoOverride: Data? = nil, caption: String) {
        title = trip.title
        dateText = trip.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        durationText = trip.durationSeconds > 0 ? TripFormat.duration(trip.durationSeconds) : nil
        distanceText = trip.distanceMeters.map(TripFormat.distance)
        carText = trip.car?.nickname.isEmpty == false ? trip.car?.nickname : nil
        self.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if let photoOverride, let image = UIImage(data: photoOverride) {
            photos = [image]
        } else {
            photos = trip.photos.sorted { $0.order < $1.order }.prefix(3).compactMap { UIImage(data: $0.data) }
        }
        route = trip.route
        scene = trip.scene
        sceneSeed = trip.sceneSeed
        isSample = trip.isDemo && SampleLabels.isVisible
    }

    var stats: [String] { [durationText, distanceText, carText].compactMap { $0 } }
}
