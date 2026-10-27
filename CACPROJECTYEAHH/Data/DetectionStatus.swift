import SwiftUI

/// What the Today screen reports about automatic trip detection.
enum DetectionStatus {
    case off, ready, possibleDriving, recording, motionPermissionNeeded, locationPermissionNeeded, unavailable

    var label: String {
        switch self {
        case .off: "Automatic detection is off"
        case .ready: "Ready to detect drives"
        case .possibleDriving: "Checking whether you're driving"
        case .recording: "Recording drive"
        case .motionPermissionNeeded: "Motion permission required"
        case .locationPermissionNeeded: "Location permission required"
        case .unavailable: "Detection unavailable"
        }
    }

    var dot: Color {
        switch self {
        case .ready, .recording, .possibleDriving: Lot.lime
        default: Lot.muted
        }
    }
}
