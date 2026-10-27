import Foundation
import SwiftData

/// Opens the local database without ever crashing the app over it.
/// If the saved data can't be opened (for example, it came from a much older version of LOT), the old files are
/// moved to a backup folder and LOT starts fresh, instead of failing at launch.
enum PersistenceController {
    static let resetFlagKey = "lot.storeWasReset"

    static let schema = Schema([
        Car.self,
        Drive.self,
        DrivePhoto.self,
        ParkingCheck.self,
        Plan.self,
        PlanStop.self,
        PlanCar.self,
        PlanPerson.self,
        RideAssignment.self,
    ])

    static func makeContainer(storeURL: URL? = nil) -> ModelContainer {
        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [config]) { return container }

        backUpStore(at: config.url)
        UserDefaults.standard.set(true, forKey: resetFlagKey)
        if let container = try? ModelContainer(for: schema, configurations: [config]) { return container }

        // Last resort so the app still opens: keep everything in memory for this session.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store with this schema can only fail if the schema itself is invalid, which is a programming error.
        return try! ModelContainer(for: schema, configurations: [memory])
    }

    /// Moves the store and its sidecar files into `StoreBackups/<timestamp>/` next to it.
    static func backUpStore(at storeURL: URL) {
        let fm = FileManager.default
        let folder = storeURL.deletingLastPathComponent()
            .appendingPathComponent("StoreBackups", isDirectory: true)
            .appendingPathComponent(String(Int(Date().timeIntervalSince1970)), isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            do { try fm.moveItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent)) }
            catch { try? fm.removeItem(at: source) }
        }
    }
}
