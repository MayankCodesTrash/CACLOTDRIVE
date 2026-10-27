import Foundation
import SwiftData

enum Skill: String, CaseIterable, Identifiable {
    case straightParking, parallelParking, reversing, merging, laneChanges
    case leftTurns, roundabouts, fourWayStops, highway, hills, rain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straightParking: "Straight-in parking"
        case .parallelParking: "Parallel parking"
        case .reversing: "Reversing"
        case .merging: "Merging"
        case .laneChanges: "Lane changes"
        case .leftTurns: "Left turns"
        case .roundabouts: "Roundabouts"
        case .fourWayStops: "Four-way stops"
        case .highway: "Highway driving"
        case .hills: "Hills"
        case .rain: "Rain"
        }
    }

    var symbol: String {
        switch self {
        case .straightParking, .parallelParking: "p.circle"
        case .reversing: "arrow.uturn.backward"
        case .merging: "arrow.triangle.merge"
        case .laneChanges: "arrow.left.arrow.right"
        case .leftTurns: "arrow.turn.up.left"
        case .roundabouts: "arrow.triangle.2.circlepath"
        case .fourWayStops: "octagon"
        case .highway: "road.lanes"
        case .hills: "mountain.2"
        case .rain: "cloud.rain"
        }
    }
}

enum ParkingManeuver: String, CaseIterable, Identifiable {
    case straightIn, parallel, angled, reverseIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straightIn: "Straight-in"
        case .parallel: "Parallel"
        case .angled: "Angled"
        case .reverseIn: "Reverse-in"
        }
    }
}

@Model
final class Car {
    var id: UUID = UUID()
    var nickname: String = ""
    var make: String = ""
    var model: String = ""
    var year: Int = 2012
    var colorHex: String = "F2F2EF"
    @Attribute(.externalStorage) var photo: Data?
    var isDemo: Bool = false
    var createdAt: Date = Date.now

    var trim: String = ""
    /// Where the user placed the car in the Garage: shifts as fractions of the width and height, and a size multiplier (1 = default).
    var garageOffsetX: Double = 0
    var garageOffsetY: Double = 0
    var garageScale: Double = 1
    /// Used to pick a matching body type when the exact car image isn't available.
    var bodyStyleRaw: String = "sedan"

    var bodyStyle: CarBodyStyle {
        get { CarBodyStyle(rawValue: bodyStyleRaw) ?? .sedan }
        set { bodyStyleRaw = newValue.rawValue }
    }

    /// Body type used to size the car in the Garage: guessed from make and model when known.
    var garageBodyStyle: CarBodyStyle { CarBodyHints.guess(make: make, model: model) ?? bodyStyle }

    @Relationship(deleteRule: .nullify, inverse: \Drive.car) var drives: [Drive] = []
    @Relationship(deleteRule: .nullify, inverse: \ParkingCheck.car) var parkingChecks: [ParkingCheck] = []

    init(nickname: String, make: String = "", model: String = "", year: Int = 2012,
         colorHex: String = "F2F2EF", photo: Data? = nil, isDemo: Bool = false) {
        self.nickname = nickname
        self.make = make
        self.model = model
        self.year = year
        self.colorHex = colorHex
        self.photo = photo
        self.isDemo = isDemo
    }
}

@Model
final class DrivePhoto {
    @Attribute(.externalStorage) var data: Data = Data()
    var order: Int = 0
    var drive: Drive?

    init(data: Data, order: Int = 0) {
        self.data = data
        self.order = order
    }
}

enum TripSource: String {
    case manual, automatic, simulated, sample

    var title: String {
        switch self {
        case .manual: "Logged manually"
        case .automatic: "Detected automatically"
        case .simulated: "Simulated sensors"
        case .sample: "Sample data"
        }
    }
}

typealias TripRecord = Drive

@Model
final class Drive {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date.now
    /// General label only ("Lake day"), never an address or route.
    var destination: String = ""
    var notes: String = ""
    var skillsRaw: [String] = []
    /// Self-rated confidence, 1...5. 0 means not rated.
    var confidence: Int = 0
    var sceneRaw: String = SceneStyle.dusk.rawValue
    var isDemo: Bool = false
    var createdAt: Date = Date.now

    // Recorded trip details. All optional so manual entries stay valid.
    var endDate: Date?
    var durationSeconds: Double = 0
    var distanceMeters: Double?
    var routeData: Data?
    var sourceRaw: String = TripSource.manual.rawValue
    var isPassenger: Bool = false
    /// True for a trip LOT detected by itself, until the user confirms whether they were driving.
    var needsReview: Bool = false
    /// Caption used on shareable recaps. Always written by the user.
    var caption: String = ""

    var car: Car?
    @Relationship(deleteRule: .cascade, inverse: \DrivePhoto.drive) var photos: [DrivePhoto] = []
    @Relationship(deleteRule: .nullify, inverse: \ParkingCheck.drive) var parkingChecks: [ParkingCheck] = []

    var skills: [Skill] {
        get { skillsRaw.compactMap(Skill.init(rawValue:)) }
        set { skillsRaw = newValue.map(\.rawValue) }
    }

    var scene: SceneStyle {
        get { SceneStyle(rawValue: sceneRaw) ?? .dusk }
        set { sceneRaw = newValue.rawValue }
    }

    var source: TripSource {
        get { TripSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var route: [RoutePoint] {
        get { routeData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? [] }
        set { routeData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var coverPhoto: Data? { photos.min { $0.order < $1.order }?.data }

    /// Stable across launches, so generated artwork never changes under the user.
    var sceneSeed: Int { id.uuidString.utf8.reduce(0) { ($0 + Int($1)) % 97 } }

    init(title: String, date: Date = .now, destination: String = "", notes: String = "",
         skills: [Skill] = [], confidence: Int = 0, scene: SceneStyle = .dusk,
         car: Car? = nil, isDemo: Bool = false) {
        self.title = title
        self.date = date
        self.destination = destination
        self.notes = notes
        self.skillsRaw = skills.map(\.rawValue)
        self.confidence = confidence
        self.sceneRaw = scene.rawValue
        self.car = car
        self.isDemo = isDemo
    }
}

enum ParkingTag: String, CaseIterable, Identifiable {
    case centered, straight, closeToCurb, crooked, offCenter, tightSpot, usedMirrors, slowAndSteady

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centered: "Centered"
        case .straight: "Straight"
        case .closeToCurb: "Close to the curb"
        case .crooked: "Crooked"
        case .offCenter: "Off-center"
        case .tightSpot: "Tight spot"
        case .usedMirrors: "Used mirrors"
        case .slowAndSteady: "Slow and steady"
        }
    }
}

/// A parking attempt. Everything here is written by the user: LOT does not score parking.
@Model
final class ParkingCheck {
    var id: UUID = UUID()
    var date: Date = Date.now
    var maneuverRaw: String = ParkingManeuver.straightIn.rawValue
    /// How many tries it took. 0 means not recorded.
    var tries: Int = 0
    var tagsRaw: [String] = []
    var note: String = ""
    @Attribute(.externalStorage) var photo: Data?
    /// Encoded `ParkingAnalysis` from the optional AI check. Nil if the user never ran it.
    var aiAnalysisData: Data?
    var isDemo: Bool = false
    var createdAt: Date = Date.now

    var car: Car?
    var drive: Drive?

    var aiAnalysis: ParkingAnalysis? {
        get { aiAnalysisData.flatMap { try? JSONDecoder().decode(ParkingAnalysis.self, from: $0) } }
        set { aiAnalysisData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var maneuver: ParkingManeuver {
        get { ParkingManeuver(rawValue: maneuverRaw) ?? .straightIn }
        set { maneuverRaw = newValue.rawValue }
    }

    var tags: [ParkingTag] {
        get { tagsRaw.compactMap(ParkingTag.init(rawValue:)) }
        set { tagsRaw = newValue.map(\.rawValue) }
    }

    init(date: Date = .now, maneuver: ParkingManeuver = .straightIn, tries: Int = 0,
         tags: [ParkingTag] = [], note: String = "", photo: Data? = nil,
         car: Car? = nil, drive: Drive? = nil, isDemo: Bool = false) {
        self.date = date
        self.maneuverRaw = maneuver.rawValue
        self.tries = tries
        self.tagsRaw = tags.map(\.rawValue)
        self.note = note
        self.photo = photo
        self.car = car
        self.drive = drive
        self.isDemo = isDemo
    }
}

// MARK: Plans

@Model
final class Plan {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date.now
    var isDemo: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \PlanStop.plan) var stops: [PlanStop] = []
    @Relationship(deleteRule: .cascade, inverse: \PlanCar.plan) var cars: [PlanCar] = []
    @Relationship(deleteRule: .cascade, inverse: \PlanPerson.plan) var people: [PlanPerson] = []

    var orderedStops: [PlanStop] { stops.sorted { $0.order < $1.order } }
    var orderedCars: [PlanCar] { cars.sorted { $0.order < $1.order } }
    var orderedPeople: [PlanPerson] { people.sorted { $0.order < $1.order } }

    init(title: String, date: Date = .now, isDemo: Bool = false) {
        self.title = title
        self.date = date
        self.isDemo = isDemo
    }
}

@Model
final class PlanStop {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var time: Date = Date.now
    var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \RideAssignment.stop) var assignments: [RideAssignment] = []

    init(order: Int, name: String, time: Date) {
        self.order = order
        self.name = name
        self.time = time
    }
}

/// A car offering rides. The driver is not counted as a passenger.
@Model
final class PlanCar {
    var id: UUID = UUID()
    var order: Int = 0
    var driverName: String = ""
    var carName: String = ""
    /// Seats available for passengers, not counting the driver.
    var seats: Int = 3
    var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \RideAssignment.car) var assignments: [RideAssignment] = []

    init(order: Int, driverName: String, carName: String, seats: Int) {
        self.order = order
        self.driverName = driverName
        self.carName = carName
        self.seats = seats
    }
}

@Model
final class PlanPerson {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \RideAssignment.person) var assignments: [RideAssignment] = []

    init(order: Int, name: String) {
        self.order = order
        self.name = name
    }
}

/// Who rides in which car on the way to a given stop.
@Model
final class RideAssignment {
    var stop: PlanStop?
    var car: PlanCar?
    var person: PlanPerson?

    init(stop: PlanStop, car: PlanCar, person: PlanPerson) {
        self.stop = stop
        self.car = car
        self.person = person
    }
}
