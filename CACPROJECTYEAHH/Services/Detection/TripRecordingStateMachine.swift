import Foundation
import CoreLocation

/// Decides when a drive starts and ends from motion and location evidence.
/// Pure logic with injected timestamps, so it can be tested without sensors.
struct TripRecordingStateMachine {
    private(set) var state: DetectionState = .idle
    let config: DetectionConfig

    private var movingSamples: [Date] = []
    private var candidateLocations: [LocationSample] = []
    private var lastAutomotiveAt: Date?
    private var lastEvidenceAt: Date?
    private var walkingSince: Date?

    private var recordingStart: Date?
    private var route: [LocationSample] = []
    private var distance = 0.0
    private var lastMovingAt: Date?
    private var stopSince: Date?

    init(config: DetectionConfig = DetectionConfig()) {
        self.config = config
    }

    mutating func handle(_ input: DetectionInput) -> [DetectionEffect] {
        guard state != .unavailable else { return [] }
        switch input {
        case .motion(let sample):
            noteMotion(sample)
            return evaluate(now: sample.date)
        case .location(let sample):
            noteLocation(sample)
            return evaluate(now: sample.date)
        case .tick(let date):
            return evaluate(now: date)
        }
    }

    mutating func setUnavailable(_ unavailable: Bool) {
        reset()
        state = unavailable ? .unavailable : .idle
    }

    /// Returns to idle, discarding any in-progress evidence. Call after handling `.completed`.
    mutating func reset() {
        state = .idle
        movingSamples = []
        candidateLocations = []
        lastAutomotiveAt = nil
        lastEvidenceAt = nil
        walkingSince = nil
        recordingStart = nil
        route = []
        distance = 0
        lastMovingAt = nil
        stopSince = nil
    }

    // MARK: Evidence

    private mutating func noteMotion(_ sample: MotionSample) {
        guard sample.confidence >= .medium else { return }
        switch sample.kind {
        case .automotive:
            lastAutomotiveAt = sample.date
            lastEvidenceAt = sample.date
            walkingSince = nil
        case .walking, .running:
            walkingSince = walkingSince ?? sample.date
        default:
            break
        }
    }

    private mutating func noteLocation(_ sample: LocationSample) {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= config.maxAccuracy else { return }

        switch state {
        case .idle, .possibleDriving:
            candidateLocations.append(sample)
            let timeout = config.possibleTimeout
            candidateLocations.removeAll { sample.date.timeIntervalSince($0.date) > timeout }
            if effectiveSpeed(of: sample, previous: candidateLocations.dropLast().last) >= config.movingSpeed {
                movingSamples.append(sample.date)
                lastEvidenceAt = sample.date
            }
        case .recording, .possibleStop:
            let speed = effectiveSpeed(of: sample, previous: route.last)
            if let last = route.last {
                let meters = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
                let seconds = sample.date.timeIntervalSince(last.date)
                // Ignore GPS jumps that would imply an impossible speed (> ~150 mph).
                if seconds > 0, meters / seconds <= 70 { distance += meters }
            }
            route.append(sample)
            if speed >= config.keepMovingSpeed { lastMovingAt = sample.date }
        default:
            break
        }
    }

    private func effectiveSpeed(of sample: LocationSample, previous: LocationSample?) -> Double {
        if sample.speed >= 0 { return sample.speed }
        guard let previous, sample.date > previous.date else { return 0 }
        let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            .distance(from: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
        return meters / sample.date.timeIntervalSince(previous.date)
    }

    // MARK: Transitions

    private mutating func evaluate(now: Date) -> [DetectionEffect] {
        switch state {
        case .idle:
            let timeout = config.possibleTimeout
            movingSamples.removeAll { now.timeIntervalSince($0) > timeout }
            if hasFreshEvidence(now: now) { state = .possibleDriving }
            return []

        case .possibleDriving:
            let timeout = config.possibleTimeout
            movingSamples.removeAll { now.timeIntervalSince($0) > timeout }
            if promotionReady(now: now), let start = movingSamples.first {
                beginRecording(start: start)
                return [.recordingStarted(start)]
            }
            if let last = lastEvidenceAt, now.timeIntervalSince(last) > config.possibleTimeout {
                reset()
            }
            return []

        case .recording:
            if let moved = lastMovingAt, now.timeIntervalSince(moved) >= config.stopCandidateAfter {
                state = .possibleStop
                stopSince = moved
            }
            return []

        case .possibleStop:
            guard let since = stopSince else { return [] }
            if let moved = lastMovingAt, moved > since {
                state = .recording
                stopSince = nil
                walkingSince = nil
                return []
            }
            let stoppedFor = now.timeIntervalSince(since)
            let walkedAway = walkingSince.map { now.timeIntervalSince($0) >= config.walkingEndsStopAfter && $0 >= since } ?? false
            if stoppedFor >= config.stopGrace || (walkedAway && stoppedFor >= config.stopCandidateAfter) {
                return finish(endingAt: since)
            }
            return []

        case .completed, .unavailable:
            return []
        }
    }

    private func hasFreshEvidence(now: Date) -> Bool {
        if !movingSamples.isEmpty { return true }
        if config.requireMotionConfirmation, let auto = lastAutomotiveAt, now.timeIntervalSince(auto) <= config.motionFreshness { return true }
        return false
    }

    /// Needs sustained speed from location, plus fresh automotive motion when required.
    private func promotionReady(now: Date) -> Bool {
        guard movingSamples.count >= config.minMovingSamples,
              let first = movingSamples.first, let last = movingSamples.last,
              last.timeIntervalSince(first) >= config.minEvidenceSeconds else { return false }
        guard config.requireMotionConfirmation else { return true }
        guard let auto = lastAutomotiveAt else { return false }
        return now.timeIntervalSince(auto) <= config.motionFreshness
    }

    private mutating func beginRecording(start: Date) {
        state = .recording
        recordingStart = start
        route = candidateLocations.filter { $0.date >= start }
        distance = 0
        for (a, b) in zip(route, route.dropFirst()) {
            distance += CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        lastMovingAt = movingSamples.last
        candidateLocations = []
        movingSamples = []
        stopSince = nil
    }

    private mutating func finish(endingAt end: Date) -> [DetectionEffect] {
        guard let start = recordingStart else { reset(); return [.tripDiscarded] }
        let kept = route.filter { $0.date <= end.addingTimeInterval(1) }
        let draft = TripDraft(
            start: start,
            end: end,
            distanceMeters: distance,
            route: Self.downsample(kept, to: config.maxRoutePoints)
        )
        if draft.duration >= config.minTripDuration, draft.distanceMeters >= config.minTripDistance {
            state = .completed
            return [.tripCompleted(draft)]
        }
        reset()
        return [.tripDiscarded]
    }

    private static func downsample(_ samples: [LocationSample], to limit: Int) -> [RoutePoint] {
        guard samples.count > limit, limit > 1 else {
            return samples.map { RoutePoint(lat: $0.latitude, lon: $0.longitude) }
        }
        let step = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { i in
            let s = samples[Int((Double(i) * step).rounded())]
            return RoutePoint(lat: s.latitude, lon: s.longitude)
        }
    }
}
