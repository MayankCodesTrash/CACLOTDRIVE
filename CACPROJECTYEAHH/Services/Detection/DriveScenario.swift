import Foundation

/// Scripted sensor data for a short drive. Used by the "Simulate a drive" demo and by tests.
/// It is fictional and never mixed up with recordings from real sensors.
struct DriveScenario {
    var inputs: [DetectionInput]

    var duration: TimeInterval {
        guard let first = inputs.first, let last = inputs.last else { return 0 }
        return Self.date(of: last).timeIntervalSince(Self.date(of: first))
    }

    static func date(of input: DetectionInput) -> Date {
        switch input {
        case .motion(let m): m.date
        case .location(let l): l.date
        case .tick(let d): d
        }
    }

    struct Options {
        var driveSeconds = 12 * 60
        var trafficLightAt: Int? = 5 * 60
        var trafficLightSeconds = 90
        var walkAwayAfterParking = true
        var includeMotion = true
        /// Extra quiet time appended so the machine can notice the trip ended.
        var trailingSeconds = 7 * 60
        /// Follow this road route instead of an invented path. Stops at its end if the drive is longer.
        var path: [RoutePoint]? = nil
    }

    /// Walk to the car, drive (with an optional red light), park, walk away.
    static func standardDrive(startingAt start: Date, options: Options = Options()) -> DriveScenario {
        var inputs: [DetectionInput] = []
        var lat = options.path?.first?.lat ?? 40.0, lon = options.path?.first?.lon ?? -90.0
        var heading = 0.6
        let step = 5

        func at(_ s: Int) -> Date { start.addingTimeInterval(TimeInterval(s)) }
        var travelled = 0.0
        func moveSample(_ s: Int, speed: Double) -> DetectionInput {
            let meters = speed * Double(step)
            if let path = options.path, path.count > 1 {
                travelled += meters
                let p = SampleRoutes.point(along: path, at: travelled)
                lat = p.lat; lon = p.lon
            } else {
                heading += 0.05 * sin(Double(s) / 40)
                lat += meters * cos(heading) / 111_000
                lon += meters * sin(heading) / (111_000 * cos(lat * .pi / 180))
            }
            return .location(LocationSample(date: at(s), latitude: lat, longitude: lon, speed: speed, horizontalAccuracy: 8))
        }

        if options.includeMotion { inputs.append(.motion(MotionSample(date: at(0), kind: .walking, confidence: .high))) }
        inputs.append(.tick(at(10)))

        let driveStart = 20
        let driveEnd = driveStart + options.driveSeconds
        if options.includeMotion { inputs.append(.motion(MotionSample(date: at(driveStart), kind: .automotive, confidence: .high))) }
        var s = driveStart
        while s < driveEnd {
            let inLight = options.trafficLightAt.map { s >= driveStart + $0 && s < driveStart + $0 + options.trafficLightSeconds } ?? false
            if inLight {
                inputs.append(.location(LocationSample(date: at(s), latitude: lat, longitude: lon, speed: 0, horizontalAccuracy: 8)))
                if options.includeMotion, (s - driveStart) % 30 == 0 {
                    // Motion sometimes reports "stationary" at a red light.
                    inputs.append(.motion(MotionSample(date: at(s), kind: .stationary, confidence: .medium)))
                }
            } else {
                let ramp = min(1.0, Double(s - driveStart) / 30)
                let speed = 12.0 * ramp * (s > driveEnd - 20 ? 0.4 : 1)
                inputs.append(moveSample(s, speed: speed))
                if options.includeMotion, (s - driveStart) % 60 == 0 {
                    inputs.append(.motion(MotionSample(date: at(s), kind: .automotive, confidence: .high)))
                }
            }
            if s % 10 == 0 { inputs.append(.tick(at(s))) }
            s += step
        }

        // Parked: stationary, then the driver walks away.
        inputs.append(.location(LocationSample(date: at(driveEnd), latitude: lat, longitude: lon, speed: 0, horizontalAccuracy: 8)))
        if options.includeMotion {
            inputs.append(.motion(MotionSample(date: at(driveEnd + 20), kind: .stationary, confidence: .high)))
            if options.walkAwayAfterParking {
                inputs.append(.motion(MotionSample(date: at(driveEnd + 50), kind: .walking, confidence: .high)))
            }
        }
        var t = driveEnd
        while t < driveEnd + options.trailingSeconds {
            t += 10
            inputs.append(.tick(at(t)))
        }
        return DriveScenario(inputs: inputs)
    }
}
