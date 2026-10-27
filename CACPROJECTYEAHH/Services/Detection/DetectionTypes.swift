import Foundation

enum DetectionState: Equatable {
    case idle, possibleDriving, recording, possibleStop, completed, unavailable
}

enum SensorAuthorization: Equatable {
    case notDetermined, denied, authorized, unavailable
}

struct MotionSample: Equatable {
    enum Kind { case automotive, stationary, walking, running, cycling, unknown }
    enum Confidence: Int, Comparable {
        case low = 0, medium, high
        static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }
    }

    var date: Date
    var kind: Kind
    var confidence: Confidence
}

struct LocationSample: Equatable {
    var date: Date
    var latitude: Double
    var longitude: Double
    /// Meters per second. Negative means the system could not determine it.
    var speed: Double
    var horizontalAccuracy: Double
}

enum DetectionInput {
    case motion(MotionSample)
    case location(LocationSample)
    /// Lets the state machine notice that time has passed when sensors go quiet.
    case tick(Date)
}

struct TripDraft: Equatable {
    var start: Date
    var end: Date
    var distanceMeters: Double
    var route: [RoutePoint]
    /// Set by simulated drives, which know where they are going. Detected trips get a time-of-day title instead.
    var title: String? = nil
    var destination: String? = nil

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum DetectionEffect: Equatable {
    case recordingStarted(Date)
    case tripCompleted(TripDraft)
    case tripDiscarded
}

/// Thresholds are configurable so they can be tuned with real-world testing.
struct DetectionConfig: Equatable {
    /// Speed that counts as "moving like a vehicle" (about 9 mph).
    var movingSpeed = 4.0
    /// Speed that counts as still moving while already recording.
    var keepMovingSpeed = 2.0
    var maxAccuracy = 100.0
    var minEvidenceSeconds = 30.0
    var minMovingSamples = 3
    var motionFreshness = 120.0
    var possibleTimeout = 120.0
    /// How long without movement before we wonder if the trip is over.
    var stopCandidateAfter = 45.0
    /// A stop this long ends the trip. Long enough to ride out red lights and drive-throughs.
    var stopGrace = 240.0
    /// Walking after a stop shortens the wait, since the driver has left the car.
    var walkingEndsStopAfter = 30.0
    var minTripDuration = 120.0
    var minTripDistance = 400.0
    var requireMotionConfirmation = true
    var maxRoutePoints = 400

    /// Used when Motion & Fitness is unavailable. Asks for stronger location evidence instead.
    static var locationOnly: DetectionConfig {
        var config = DetectionConfig()
        config.requireMotionConfirmation = false
        config.movingSpeed = 6
        config.minEvidenceSeconds = 60
        config.minMovingSamples = 5
        return config
    }
}
