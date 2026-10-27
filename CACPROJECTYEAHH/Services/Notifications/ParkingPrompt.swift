import Foundation
import UserNotifications

/// The slice of the notification center LOT uses, so tests can stand in for it.
protocol NotificationScheduling {
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async
    func setCategories(_ categories: Set<UNNotificationCategory>)
}

struct SystemNotificationCenter: NotificationScheduling {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ request: UNNotificationRequest) async {
        try? await UNUserNotificationCenter.current().add(request)
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

/// After a drive ends, offers a parking photo. Sent only once the drive is over (the car has stopped), never during one.
@MainActor
final class ParkingPromptCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ParkingPromptCenter()
    static let categoryID = "lot.parkingPrompt"
    static let photoActionID = "lot.takePhoto"
    static let tripKey = "tripID"

    var center: NotificationScheduling = SystemNotificationCenter()
    /// Called when the user taps the notification (or its "Take photo" action).
    var onOpenParking: ((UUID) -> Void)?

    /// Call once at launch: lets notifications show while the app is open, and registers the "Take photo" action.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        center.setCategories(Self.categories)
    }

    static var categories: Set<UNNotificationCategory> {
        let photo = UNNotificationAction(identifier: photoActionID, title: "Take photo", options: [.foreground])
        return [UNNotificationCategory(identifier: categoryID, actions: [photo], intentIdentifiers: [], options: [])]
    }

    func requestAuthorization() async -> Bool { await center.requestAuthorization() }

    static func content(tripID: UUID, tripTitle: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Parked? Add a parking photo"
        content.body = "\"\(tripTitle)\" is saved. Only take the photo once you're out of the car."
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "lot.parking"
        content.userInfo = [tripKey: tripID.uuidString]
        content.sound = .default
        return content
    }

    func notifyParked(tripID: UUID, tripTitle: String) async {
        guard await center.requestAuthorization() else { return }
        let request = UNNotificationRequest(
            identifier: "lot.parking.\(tripID.uuidString)",
            content: Self.content(tripID: tripID, tripTitle: tripTitle),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        await center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[Self.tripKey] as? String, let id = UUID(uuidString: text) else { return }
        await MainActor.run { onOpenParking?(id) }
    }
}
