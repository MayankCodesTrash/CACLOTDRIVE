import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = LotRouter()
    @State private var detection = TripDetectionService()
    @State private var showResetNotice = UserDefaults.standard.bool(forKey: PersistenceController.resetFlagKey)

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
            Group {
                switch router.tab {
                case .today: TodayView()
                case .drives: DrivesView()
                case .park: ParkView()
                case .plans: PlansView()
                case .garage: GarageView()
                }
            }
            .id(router.tab)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floats over the content. Every scroll view leaves `Lot.Space.tabBarClearance` at its bottom so nothing hides behind it.
            LotTabBar(selection: $router.tab)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, Lot.charcoal.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                )
        }
        .lotScreen()
        .animation(.smooth(duration: 0.3), value: router.tab)
        .environment(router)
        .environment(detection)
        .alert("Your data was reset", isPresented: $showResetNotice) {
            Button("OK") { UserDefaults.standard.set(false, forKey: PersistenceController.resetFlagKey) }
        } message: {
            Text("LOT couldn't open the data saved by an older version, so it started fresh. The old data was kept in a backup folder on this phone.")
        }
        .task {
            detection.configure(repository: TripRepository(context: context))
            ParkingPromptCenter.shared.configure()
            ParkingPromptCenter.shared.onOpenParking = { tripID in router.startParkCheck(forTrip: tripID) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { detection.refreshAuthorization() }
        }
        #if DEBUG
        .task {
            // `-loadSampleData` launch argument: preload demo entries for screenshots and testing.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count, let tab = LotTab(rawValue: args[i + 1]) { router.tab = tab }
            if args.contains("-newDrive") { router.composingDrive = true }
            if args.contains("-debugVehiclePipeline") { await VehicleImageStore.debugPipeline() }
            if let i = args.firstIndex(of: "-simulateNames"), i + 1 < args.count {
                let names = args[i + 1].split(separator: "|").map(String.init)
                if names.count == 2, let from = await RouteFinder.resolve(names[0]), let to = await RouteFinder.resolve(names[1]),
                   let route = try? await RouteFinder.driving(from: from.item, to: to.item) {
                    await detection.simulateDrive(.init(path: route.points, title: "Drive to \(to.name)", destination: to.name))
                }
            }
            if args.contains("-simulateDrive") {
                try? await Task.sleep(for: .seconds(1))
                await detection.simulateDrive(paceMilliseconds: 8)
            }
            if args.contains("-loadSampleData"),
               ((try? context.fetchCount(FetchDescriptor<Drive>())) ?? 0) == 0 {
                SampleData.load(into: context)
            }
        }
        #endif
    }
}
