import SwiftUI
import SwiftData

@main
struct CACPROJECTYEAHHApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Lot.lime)
        }
        .modelContainer(sharedModelContainer)
    }
}
