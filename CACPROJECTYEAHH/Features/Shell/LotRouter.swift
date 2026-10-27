import SwiftUI

/// App-wide navigation state. Quick actions on Today use it to jump to a tab
/// and ask that tab to open its composer.
@Observable
final class LotRouter {
    var tab: LotTab = .today
    var composingDrive = false
    var composingParkCheck = false
    /// The drive a new parking photo should be attached to, when it came from a "Parked?" prompt.
    var parkTripID: UUID?

    func logDrive() {
        tab = .drives
        composingDrive = true
    }

    func startParkCheck(forTrip tripID: UUID? = nil) {
        parkTripID = tripID
        tab = .park
        composingParkCheck = true
    }
}
