import Foundation
import SwiftUI
import Observation

/// Owns the sensor providers and the state machine, and reports honest status to the UI.
/// Detection runs only while LOT is open: no background location mode is enabled.
@Observable
final class TripDetectionService {
    private(set) var state: DetectionState = .idle
    private(set) var isEnabled: Bool
    private(set) var isSimulating = false
    private(set) var motionAuth: SensorAuthorization = .notDetermined
    private(set) var locationAuth: SensorAuthorization = .notDetermined

    @ObservationIgnored private let motion: MotionActivityProvider
    @ObservationIgnored private let location: LocationProvider
    @ObservationIgnored private var repository: TripRepository?
    @ObservationIgnored private var machine = TripRecordingStateMachine()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var currentSource: TripSource = .automatic
    @ObservationIgnored private var pendingSimulation: SimulatedTrip?
    @ObservationIgnored private static let enabledKey = "lot.detection.enabled"

    init(motion: MotionActivityProvider = CoreMotionActivityProvider(),
         location: LocationProvider = CoreLocationProvider()) {
        self.motion = motion
        self.location = location
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func configure(repository: TripRepository) {
        self.repository = repository
        refreshAuthorization()
        if isEnabled { Task { await start() } }
    }

    // MARK: Status

    var status: DetectionStatus {
        if isSimulating {
            switch state {
            case .possibleDriving: return .possibleDriving
            case .recording, .possibleStop: return .recording
            default: return .ready
            }
        }
        guard isEnabled else { return .off }
        if locationAuth == .denied { return .locationPermissionNeeded }
        if locationAuth == .unavailable { return .unavailable }
        if motionAuth == .denied { return .motionPermissionNeeded }
        switch state {
        case .idle, .completed: return .ready
        case .possibleDriving: return .possibleDriving
        case .recording, .possibleStop: return .recording
        case .unavailable: return .unavailable
        }
    }

    var statusLabel: String {
        isSimulating ? "Simulated · \(status.label)" : status.label
    }

    /// True when Motion & Fitness can't be used, so location alone has to carry detection.
    var usesLocationOnly: Bool { motionAuth == .denied || motionAuth == .unavailable }

    func refreshAuthorization() {
        motionAuth = motion.authorization
        locationAuth = location.authorization
    }

    // MARK: Enable / disable

    func setEnabled(_ on: Bool) async {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            _ = await ParkingPromptCenter.shared.requestAuthorization()
            await motion.requestAuthorization()
            await location.requestAuthorization()
            refreshAuthorization()
            await start()
        } else {
            stop()
        }
    }

    private func start() async {
        stop()
        refreshAuthorization()
        guard locationAuth == .authorized else {
            machine = TripRecordingStateMachine()
            machine.setUnavailable(true)
            state = machine.state
            return
        }
        let config: DetectionConfig = usesLocationOnly ? .locationOnly : DetectionConfig()
        machine = TripRecordingStateMachine(config: config)
        state = .idle
        currentSource = .automatic

        if motionAuth == .authorized {
            let stream = motion.updates()
            tasks.append(Task { for await sample in stream { ingest(.motion(sample)) } })
        }
        let locationStream = location.updates()
        tasks.append(Task { for await sample in locationStream { ingest(.location(sample)) } })
        tasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                ingest(.tick(.now))
            }
        })
    }

    private func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        machine.reset()
        state = .idle
    }

    // MARK: Simulation

    /// A drive to replay: a road route plus where it goes.
    struct SimulatedTrip {
        var path: [RoutePoint]
        var title: String
        var destination: String
    }

    /// Replays scripted sensor data along a route, through the same pipeline as a real drive. The saved trip is labeled
    /// "Simulated sensors" and is never confused with a real recording. With no trip given, it uses a built-in sample route.
    func simulateDrive(_ trip: SimulatedTrip? = nil, paceMilliseconds: Int? = nil) async {
        guard !isSimulating else { return }
        isSimulating = true
        _ = await ParkingPromptCenter.shared.requestAuthorization()
        let previous = machine

        let path = Self.thinned(trip?.path ?? SampleRoutes.route(at: 5), to: 1500)
        let length = SampleRoutes.length(of: path)
        var options = DriveScenario.Options()
        options.path = path
        // Longer routes are mostly highway, so assume a faster average. No upper limit on length.
        let metersPerSecond = length > 30_000 ? 24.0 : (length > 10_000 ? 17.0 : 11.0)
        options.driveSeconds = Int(max(length / metersPerSecond, 150))
        options.trafficLightAt = options.driveSeconds > 360 ? Int(Double(options.driveSeconds) * 0.4) : nil
        // The drive ends "now", so the saved trip is the most recent one.
        let scenario = DriveScenario.standardDrive(startingAt: .now.addingTimeInterval(-Double(options.driveSeconds + 20)), options: options)

        machine = TripRecordingStateMachine()
        currentSource = .simulated
        pendingSimulation = trip
        state = .idle

        let pace = paceMilliseconds ?? min(15, max(1, 10_000 / max(scenario.inputs.count, 1)))
        for input in scenario.inputs {
            ingest(input, fromSimulation: true)
            try? await Task.sleep(for: .milliseconds(pace))
        }

        machine = previous
        machine.reset()
        state = .idle
        currentSource = .automatic
        pendingSimulation = nil
        isSimulating = false
    }

    /// Keeps at most `limit` points, always including the first and last.
    nonisolated static func thinned(_ points: [RoutePoint], to limit: Int) -> [RoutePoint] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }

    // MARK: Pipeline

    private func ingest(_ input: DetectionInput, fromSimulation: Bool = false) {
        if isSimulating && !fromSimulation { return }
        let effects = machine.handle(input)
        state = machine.state
        for effect in effects {
            switch effect {
            case .tripCompleted(var draft):
                if currentSource == .simulated, let simulated = pendingSimulation {
                    draft.title = simulated.title
                    draft.destination = simulated.destination
                }
                if let trip = repository?.save(draft, source: currentSource) {
                    // The car has stopped, so it's safe to offer a parking photo. Never sent during a drive.
                    let id = trip.id, title = trip.title
                    Task { await ParkingPromptCenter.shared.notifyParked(tripID: id, tripTitle: title) }
                }
                machine.reset()
                state = machine.state
            case .recordingStarted, .tripDiscarded:
                break
            }
        }
    }
}
