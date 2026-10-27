import Foundation
import SwiftData

/// Seating rules for an outing. Assignments are per stop, so rides can change between stops.
extension Plan {
    func riders(in car: PlanCar, at stop: PlanStop) -> [PlanPerson] {
        stop.assignments
            .filter { $0.car?.id == car.id }
            .compactMap(\.person)
            .sorted { $0.order < $1.order }
    }

    func seatsLeft(in car: PlanCar, at stop: PlanStop) -> Int {
        max(0, car.seats - riders(in: car, at: stop).count)
    }

    func assignment(of person: PlanPerson, at stop: PlanStop) -> RideAssignment? {
        stop.assignments.first { $0.person?.id == person.id }
    }

    func unassigned(at stop: PlanStop) -> [PlanPerson] {
        orderedPeople.filter { assignment(of: $0, at: stop) == nil }
    }

    var totalSeats: Int { cars.reduce(0) { $0 + $1.seats } }

    func filledSeats(at stop: PlanStop) -> Int {
        stop.assignments.filter { $0.car != nil && $0.person != nil }.count
    }

    /// Puts a passenger in a car for a stop. Returns false, changing nothing, if the car is full.
    @discardableResult
    func assign(_ person: PlanPerson, to car: PlanCar, at stop: PlanStop, in context: ModelContext) -> Bool {
        if let existing = assignment(of: person, at: stop) {
            if existing.car?.id == car.id { return true }
            guard seatsLeft(in: car, at: stop) > 0 else { return false }
            existing.car = car
            return true
        }
        guard seatsLeft(in: car, at: stop) > 0 else { return false }
        context.insert(RideAssignment(stop: stop, car: car, person: person))
        return true
    }

    func unassign(_ person: PlanPerson, at stop: PlanStop, in context: ModelContext) {
        if let existing = assignment(of: person, at: stop) { context.delete(existing) }
    }

    /// Copies rides from one stop to another, skipping anyone who no longer fits.
    func copyAssignments(from source: PlanStop, to target: PlanStop, in context: ModelContext) {
        for existing in target.assignments { context.delete(existing) }
        // Deleting is lazy until saved, so count only what we add here.
        var used: [UUID: Int] = [:]
        for assignment in source.assignments {
            guard let car = assignment.car, let person = assignment.person else { continue }
            if used[car.id, default: 0] < car.seats {
                used[car.id, default: 0] += 1
                context.insert(RideAssignment(stop: target, car: car, person: person))
            }
        }
    }

    /// After seat counts shrink, drops the last riders so no car is over capacity.
    func trimOverCapacity(in context: ModelContext) {
        for stop in stops {
            for car in cars {
                let current = stop.assignments
                    .filter { $0.car?.id == car.id }
                    .sorted { ($0.person?.order ?? 0) < ($1.person?.order ?? 0) }
                if current.count > car.seats {
                    for extra in current.dropFirst(car.seats) { context.delete(extra) }
                }
            }
        }
    }
}

/// A plain-value snapshot of a plan, used for the shareable image and text.
struct PlanSummary {
    struct Stop: Identifiable {
        let id = UUID()
        let time: String
        let name: String
        let rides: [String]
        let needsRide: [String]
    }

    let title: String
    let dateText: String
    let stops: [Stop]
    let isSample: Bool

    @MainActor
    init(plan: Plan) {
        title = plan.title
        dateText = plan.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        isSample = plan.isDemo && SampleLabels.isVisible
        stops = plan.orderedStops.map { stop in
            let rides = plan.orderedCars.compactMap { car -> String? in
                let names = plan.riders(in: car, at: stop).map(\.name)
                guard !names.isEmpty else { return nil }
                let label = car.carName.isEmpty ? car.driverName : "\(car.driverName) (\(car.carName))"
                return "\(label): \(names.joined(separator: ", "))"
            }
            let needs = stop.assignments.isEmpty ? [] : plan.unassigned(at: stop).map(\.name)
            return Stop(time: stop.time.formatted(.dateTime.hour().minute()), name: stop.name, rides: rides, needsRide: needs)
        }
    }

    var text: String {
        var lines = [title, dateText, ""]
        for stop in stops {
            lines.append("\(stop.time)  \(stop.name)")
            for ride in stop.rides { lines.append("   \(ride)") }
            if !stop.needsRide.isEmpty { lines.append("   Still needs a ride: \(stop.needsRide.joined(separator: ", "))") }
        }
        lines.append("")
        lines.append(isSample ? "Sample plan · Made with LOT" : "Made with LOT")
        return lines.joined(separator: "\n")
    }
}
