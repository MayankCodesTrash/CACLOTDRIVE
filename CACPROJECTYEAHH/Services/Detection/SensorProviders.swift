import Foundation
import CoreMotion
import CoreLocation

protocol MotionActivityProvider: AnyObject {
    var authorization: SensorAuthorization { get }
    func requestAuthorization() async
    func updates() -> AsyncStream<MotionSample>
}

protocol LocationProvider: AnyObject {
    var authorization: SensorAuthorization { get }
    func requestAuthorization() async
    func updates() -> AsyncStream<LocationSample>
}

/// Real motion activity from CMMotionActivityManager. Unavailable in the simulator.
final class CoreMotionActivityProvider: MotionActivityProvider {
    private let manager = CMMotionActivityManager()

    var authorization: SensorAuthorization {
        guard CMMotionActivityManager.isActivityAvailable() else { return .unavailable }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async {
        guard authorization == .notDetermined else { return }
        // Asking for a small slice of history triggers the system permission prompt.
        await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: .main) { _, _ in
                continuation.resume()
            }
        }
    }

    func updates() -> AsyncStream<MotionSample> {
        AsyncStream { continuation in
            manager.startActivityUpdates(to: .main) { activity in
                guard let activity else { return }
                let kind: MotionSample.Kind =
                    activity.automotive ? .automotive :
                    activity.walking ? .walking :
                    activity.running ? .running :
                    activity.cycling ? .cycling :
                    activity.stationary ? .stationary : .unknown
                let confidence: MotionSample.Confidence =
                    activity.confidence == .high ? .high : activity.confidence == .medium ? .medium : .low
                continuation.yield(MotionSample(date: activity.startDate, kind: kind, confidence: confidence))
            }
            continuation.onTermination = { [manager] _ in manager.stopActivityUpdates() }
        }
    }
}

/// Real location from CLLocationManager, foreground only (no background location mode is enabled).
final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var streamContinuation: AsyncStream<LocationSample>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: SensorAuthorization {
        guard CLLocationManager.locationServicesEnabled() else { return .unavailable }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func updates() -> AsyncStream<LocationSample> {
        AsyncStream { continuation in
            streamContinuation = continuation
            manager.startUpdatingLocation()
            continuation.onTermination = { [manager] _ in
                Task { @MainActor in manager.stopUpdatingLocation() }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authContinuation?.resume()
        authContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            streamContinuation?.yield(LocationSample(
                date: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                speed: location.speed,
                horizontalAccuracy: location.horizontalAccuracy
            ))
        }
    }
}
