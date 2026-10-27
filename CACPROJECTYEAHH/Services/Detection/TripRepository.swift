import Foundation
import SwiftData

/// Turns detected trips into saved `Drive` records, and handles the small edits users can make.
struct TripRepository {
    let context: ModelContext

    @discardableResult
    func save(_ draft: TripDraft, source: TripSource) -> Drive {
        let trip = Drive(
            title: draft.title ?? TripFormat.timeOfDayTitle(for: draft.start),
            date: draft.start,
            destination: draft.destination ?? "",
            scene: SceneStyle.forTime(draft.start),
            isDemo: source == .sample
        )
        // Anything LOT detected on its own needs the user's say-so: were they driving, or a passenger, or was it a false alarm?
        trip.needsReview = source == .automatic || source == .simulated
        trip.endDate = draft.end
        trip.durationSeconds = draft.duration
        trip.distanceMeters = draft.distanceMeters
        trip.route = draft.route
        trip.source = source

        // Only guess the car when there is exactly one to choose from.
        let cars = (try? context.fetch(FetchDescriptor<Car>())) ?? []
        if cars.count == 1 { trip.car = cars.first }

        context.insert(trip)
        return trip
    }

    func delete(_ trip: Drive) {
        context.delete(trip)
    }

    func setPassenger(_ trip: Drive, _ isPassenger: Bool) {
        trip.isPassenger = isPassenger
    }

    /// The user's answer to "Was this you driving?".
    enum Review { case iDrove, passenger }

    func review(_ trip: Drive, as answer: Review) {
        trip.isPassenger = answer == .passenger
        trip.needsReview = false
    }
}
