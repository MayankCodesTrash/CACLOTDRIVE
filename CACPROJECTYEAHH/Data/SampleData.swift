import Foundation
import SwiftData

/// Fictional sample entries so the app can be demoed with history.
/// Everything inserted here is flagged `isDemo` and can be removed in one tap.
enum SampleData {
    private struct SampleTrip {
        let title: String, label: String, daysAgo: Int, hour: Double, minutes: Double, miles: Double
        let scene: SceneStyle, notes: String
    }

    /// Days back to the most recent given weekday (Sunday = 1), never today.
    private static func daysSince(weekday: Int) -> Int {
        let diff = (Calendar.current.component(.weekday, from: .now) - weekday + 7) % 7
        return diff == 0 ? 7 : diff
    }

    private static var trips: [SampleTrip] { [
        SampleTrip(title: "Morning drive to school", label: "School", daysAgo: 1, hour: 7.4, minutes: 14, miles: 4.6, scene: .coast, notes: "Left early so I could take the student lot slowly."),
        SampleTrip(title: "After-school food run", label: "Food run", daysAgo: 1, hour: 15.6, minutes: 22, miles: 7.1, scene: .mesa, notes: ""),
        SampleTrip(title: "Friday football game", label: "Football game", daysAgo: daysSince(weekday: 6), hour: 18.2, minutes: 19, miles: 5.8, scene: .dusk, notes: "Parked way out and walked. Worth it."),
        SampleTrip(title: "Driving to practice", label: "Practice", daysAgo: 5, hour: 15.3, minutes: 17, miles: 6.2, scene: .overcast, notes: ""),
        SampleTrip(title: "First solo drive", label: "Home", daysAgo: 9, hour: 16.1, minutes: 11, miles: 2.9, scene: .forest, notes: "First time with nobody in the passenger seat. Kept the music off."),
        SampleTrip(title: "Weekend mall trip", label: "Mall", daysAgo: daysSince(weekday: 7) + 7, hour: 13.2, minutes: 31, miles: 12.4, scene: .mesa, notes: ""),
        SampleTrip(title: "Homecoming pictures", label: "Homecoming", daysAgo: 16, hour: 16.4, minutes: 26, miles: 8.3, scene: .dusk, notes: ""),
        SampleTrip(title: "Friend's house", label: "Friend's house", daysAgo: 20, hour: 19.0, minutes: 15, miles: 5.1, scene: .night, notes: ""),
    ]}

    private static let checks: [(Int, ParkingManeuver, Int, [ParkingTag], String, Int?)] = [
        (24, .straightIn, 4, [.crooked, .tightSpot], "Turned in too late. Aim for the middle of the space.", nil),
        (19, .straightIn, 3, [.offCenter], "Better speed control, still drifted left.", nil),
        (15, .parallel, 4, [.tightSpot], "Stopped too far from the curb.", nil),
        (11, .straightIn, 2, [.centered, .usedMirrors], "", 4),
        (7, .reverseIn, 3, [.usedMirrors, .slowAndSteady], "Straighten the wheel sooner.", nil),
        (4, .straightIn, 1, [.centered, .straight], "First try in the student lot.", 2),
        (2, .parallel, 2, [.closeToCurb], "One adjustment.", nil),
        (1, .straightIn, 1, [.centered, .straight, .slowAndSteady], "", 0),
    ]

    @MainActor
    static func load(into context: ModelContext) {
        let car = Car(nickname: "Biscuit", make: "Honda", model: "Civic", year: 2009, colorHex: "E98A2B", isDemo: true)
        context.insert(car)

        let cal = Calendar.current
        var created: [Drive] = []
        for (index, item) in trips.enumerated() {
            let day = cal.date(byAdding: .day, value: -item.daysAgo, to: cal.startOfDay(for: .now)) ?? .now
            let start = day.addingTimeInterval(item.hour * 3600)
            let trip = Drive(title: item.title, date: start, destination: item.label, notes: item.notes,
                             scene: item.scene, car: car, isDemo: true)
            trip.durationSeconds = item.minutes * 60
            trip.endDate = start.addingTimeInterval(item.minutes * 60)
            let road = SampleRoutes.route(at: index)
            trip.route = road
            trip.distanceMeters = SampleRoutes.length(of: road)
            trip.source = .sample
            context.insert(trip)
            created.append(trip)
        }

        loadPlan(into: context)

        // `checks` is oldest first, so index i lines up with `SampleParking.quality[i]`.
        for (index, item) in checks.enumerated() {
            let day = cal.date(byAdding: .day, value: -item.0, to: .now) ?? .now
            let quality = SampleParking.quality[min(index, SampleParking.quality.count - 1)]
            let check = ParkingCheck(date: day, maneuver: item.1, tries: item.2, tags: item.3, note: item.4,
                                     photo: SampleParking.image(quality: quality, seed: index),
                                     car: car, drive: item.5.map { created[$0] }, isDemo: true)
            check.aiAnalysis = SampleParking.analysis(quality: quality, date: day)
            context.insert(check)
        }
    }

    /// "HOCO Night": four stops, two cars, six riders, with one rider still needing a ride at the first stop.
    @MainActor
    private static func loadPlan(into context: ModelContext) {
        let cal = Calendar.current
        let daysAhead = { () -> Int in
            let diff = (6 - cal.component(.weekday, from: .now) + 7) % 7
            return diff == 0 ? 7 : diff
        }()
        let day = cal.date(byAdding: .day, value: daysAhead, to: cal.startOfDay(for: .now)) ?? .now
        func at(_ hour: Int, _ minute: Int) -> Date { cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day }

        let plan = Plan(title: "HOCO Night", date: at(16, 30), isDemo: true)
        context.insert(plan)

        let stops = [("Pictures", at(16, 30)), ("Dinner", at(17, 45)), ("Homecoming", at(19, 30)), ("After-event meetup", at(22, 30))]
            .enumerated().map { PlanStop(order: $0.offset, name: $0.element.0, time: $0.element.1) }
        for stop in stops { context.insert(stop); stop.plan = plan }

        let cars = [PlanCar(order: 0, driverName: "Theo", carName: "Old Blue", seats: 3),
                    PlanCar(order: 1, driverName: "Nia", carName: "Marigold", seats: 4)]
        for car in cars { context.insert(car); car.plan = plan }

        let people = ["Juniper", "Ravi", "Dex", "Sam", "Priya", "Mia"].enumerated().map { PlanPerson(order: $0.offset, name: $0.element) }
        for person in people { context.insert(person); person.plan = plan }

        // Per stop: which car each rider (by index) is in. nil leaves them without a ride.
        let rides: [[Int?]] = [
            [0, 0, 0, 1, 1, nil],
            [0, 0, 1, 1, 1, 1],
            [0, 0, 0, 1, 1, 1],
            [nil, nil, nil, nil, nil, nil],
        ]
        for (stopIndex, row) in rides.enumerated() {
            for (personIndex, carIndex) in row.enumerated() {
                guard let carIndex else { continue }
                context.insert(RideAssignment(stop: stops[stopIndex], car: cars[carIndex], person: people[personIndex]))
            }
        }
    }

    @MainActor
    static func clear(from context: ModelContext) {
        try? context.delete(model: Plan.self, where: #Predicate { $0.isDemo })
        try? context.delete(model: ParkingCheck.self, where: #Predicate { $0.isDemo })
        try? context.delete(model: Drive.self, where: #Predicate { $0.isDemo })
        try? context.delete(model: Car.self, where: #Predicate { $0.isDemo })
    }

    static func hasSample(in context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<Drive>(predicate: #Predicate { $0.isDemo }))) ?? 0
        return count > 0
    }
}
