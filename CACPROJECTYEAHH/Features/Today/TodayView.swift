import SwiftUI
import SwiftData

enum ProgressRoute: Hashable { case overview }

struct TodayView: View {
    @Environment(LotRouter.self) private var router
    @Environment(TripDetectionService.self) private var detection
    @Query(sort: \Drive.date, order: .reverse) private var drives: [Drive]
    @Query(sort: \ParkingCheck.date, order: .reverse) private var checks: [ParkingCheck]
    @Query(sort: \Plan.date) private var plans: [Plan]

    @State private var path = NavigationPath()
    @State private var recapTrip: Drive?
    @State private var showSettings = false

    private var trips: [Drive] { drives.filter { !$0.isPassenger } }
    private var hasSample: Bool { drives.contains(where: \.isDemo) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    DetectionSwitchRow()
                        .padding(.horizontal, Lot.Space.gutter)
                        .padding(.top, -12)

                    if let pending = drives.first(where: { $0.needsReview }) {
                        NavigationLink(value: pending) {
                            HStack(spacing: 14) {
                                Image(systemName: "questionmark.circle.fill").font(.title2).foregroundStyle(Lot.lime)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Was this you driving?").font(LotType.title).foregroundStyle(Lot.warmWhite)
                                    Text(pending.title).font(LotType.caption).foregroundStyle(Lot.muted).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Lot.charcoalRaised))
                            .padding(.horizontal, Lot.Space.gutter)
                        }
                        .buttonStyle(.plain)
                    }

                    if let latest = trips.first {
                        FeaturedTripCard(trip: latest) { recapTrip = latest }
                    } else {
                        EmptyTodayState(onSetup: { showSettings = true }, onManual: { router.logDrive() })
                    }

                    if let plan = nextPlan { planPreview(plan) }
                    parkShortcut
                    if !drives.isEmpty || !checks.isEmpty { progressPreview }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .clearsTabBar()
            .toolbar(.hidden, for: .navigationBar)
            .lotScreen()
            .navigationDestination(for: Drive.self) { TripDetailView(trip: $0) }
            .navigationDestination(for: ProgressRoute.self) { _ in ProgressOverviewView() }
        }
        .sheet(item: $recapTrip) { trip in
            RecapSheet(trip: trip).presentationBackground(Lot.charcoal)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationBackground(Lot.charcoal)
        }
        #if DEBUG
        .task { await debugHooks() }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    Text("LOT").font(.system(.subheadline, weight: .black)).foregroundStyle(Lot.warmWhite)
                    Circle().fill(Lot.lime).frame(width: 5, height: 5)
                }
                Text(greeting).font(LotType.display).foregroundStyle(Lot.warmWhite)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Lot.warmWhite)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Profile and settings")
        }
        .padding(.horizontal, Lot.Space.gutter)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Upcoming plan

    private var nextPlan: Plan? {
        plans.first { $0.date >= Date.now.addingTimeInterval(-3 * 3600) }
    }

    private func planPreview(_ plan: Plan) -> some View {
        Button { router.tab = .plans } label: {
            HStack(spacing: 16) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(Lot.warmWhite)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Lot.elevated))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(LotType.title).foregroundStyle(Lot.warmWhite)
                        if plan.isDemo { DemoBadge() }
                    }
                    Text(planSubtitle(plan)).font(LotType.caption).foregroundStyle(Lot.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Lot.charcoalRaised))
            .padding(.horizontal, Lot.Space.gutter)
        }
        .buttonStyle(.plain)
    }

    private func planSubtitle(_ plan: Plan) -> String {
        var parts = [TripFormat.dayAndTime(plan.orderedStops.first?.time ?? plan.date)]
        if let first = plan.orderedStops.first, plan.totalSeats > 0 {
            parts.append("\(plan.filledSeats(at: first)) of \(plan.totalSeats) seats filled")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Park shortcut

    private var parkShortcut: some View {
        Button { router.startParkCheck() } label: {
            HStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Lot.lime)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Lot.elevated))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Park check").font(LotType.title).foregroundStyle(Lot.warmWhite)
                    Text(checks.isEmpty ? "Photograph where you parked. Private to you." : "\(checks.count) saved · private to you")
                        .font(LotType.caption).foregroundStyle(Lot.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Lot.charcoalRaised))
            .padding(.horizontal, Lot.Space.gutter)
        }
        .buttonStyle(.plain)
    }

    // MARK: Progress

    private var progressPreview: some View {
        let stats = ProgressStats(trips: drives, checks: checks)
        return NavigationLink(value: ProgressRoute.overview) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your progress").font(LotType.title).foregroundStyle(Lot.warmWhite)
                    Text("\(stats.tripCount) trips · \(stats.parkingCheckCount) parking checks · \(stats.reflectionCount) reflections")
                        .font(LotType.caption).foregroundStyle(Lot.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
            }
            .padding(.horizontal, Lot.Space.gutter)
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    private func debugHooks() async {
        try? await Task.sleep(for: .milliseconds(800))
        let args = CommandLine.arguments
        if args.contains("-showDetail"), let trip = trips.first { path.append(trip) }
        if args.contains("-showRecap"), let trip = trips.first { recapTrip = trip }
        if args.contains("-showSettings") { showSettings = true }
        if args.contains("-showProgress") { path.append(ProgressRoute.overview) }
        if args.contains("-dumpRecaps"), let trip = trips.first {
            for style in RecapStyle.allCases {
                let image = RecapRenderer.image(style: style, content: RecapContent(trip: trip, caption: "Left early, took it slow."))
                try? image?.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recap-\(style.rawValue).png"))
            }
        }
    }
    #endif
}

/// One switch: automatic drive detection on or off. A line of help appears only if it can't run, such as a missing permission.
private struct DetectionSwitchRow: View {
    @Environment(TripDetectionService.self) private var detection
    @Environment(\.openURL) private var openURL

    private var needsHelp: Bool {
        detection.isEnabled && (detection.status == .locationPermissionNeeded || detection.status == .motionPermissionNeeded || detection.status == .unavailable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { detection.isEnabled }, set: { on in Task { await detection.setEnabled(on) } })) {
                HStack(spacing: 10) {
                    Image(systemName: "location.viewfinder").foregroundStyle(Lot.warmWhite)
                    Text("Automatic detection").font(LotType.body.weight(.medium)).foregroundStyle(Lot.warmWhite)
                }
            }
            .tint(Lot.lime)
            .frame(minHeight: 44)

            if needsHelp {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(detection.status.label + ". Tap to open Settings.").font(LotType.labelSmall).foregroundStyle(Lot.muted)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Shown until the first real trip exists. No invented activity.
private struct EmptyTodayState: View {
    let onSetup: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SceneArt(style: .night, seed: 6)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text("Your first drive\nshows up here.")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Lot.warmWhite)
                        .padding(22)
                }
            Text("LOT can notice your drives and save them for you, so you can reflect and share them after you park. Turn on detection, or add a past drive yourself.")
                .font(LotType.body).foregroundStyle(Lot.muted)
                .padding(.top, 20)
            HStack(spacing: 12) {
                Button("Set up detection", action: onSetup).buttonStyle(LotButtonStyle())
                Button("Add a drive", action: onManual).buttonStyle(LotButtonStyle(kind: .ghost))
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, Lot.Space.gutter)
    }
}
