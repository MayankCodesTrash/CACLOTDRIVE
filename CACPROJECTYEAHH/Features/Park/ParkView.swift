import SwiftUI
import SwiftData
import PhotosUI

private struct ParkDraft: Identifiable {
    let id = UUID()
    let photo: Data
    /// The drive this photo belongs to, if it came from a "Parked?" prompt.
    var tripID: UUID?
}

struct ParkView: View {
    @Environment(LotRouter.self) private var router
    @Query(sort: \ParkingCheck.date, order: .reverse) private var checks: [ParkingCheck]
    @Query private var drives: [Drive]

    @State private var path = NavigationPath()
    @State private var wantsCamera = true
    @State private var showGate = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var draft: ParkDraft?
    @State private var pendingTripID: UUID?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    LotHeader(title: "Park") { EmptyView() }
                    capturePanel
                    if checks.isEmpty {
                        emptyHistory
                    } else {
                        progress
                        history
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .clearsTabBar()
            .toolbar(.hidden, for: .navigationBar)
            .lotScreen()
            .navigationDestination(for: ParkingCheck.self) { ParkDetailView(check: $0) }
        }
        .confirmationDialog("Are you parked?", isPresented: $showGate, titleVisibility: .visible) {
            Button("I'm parked and out of the car") {
                if wantsCamera && CameraPicker.isAvailable { showCamera = true } else { showLibrary = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only add a parking photo once you've stopped and stepped out of the car.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in if let data { draft = ParkDraft(photo: data, tripID: pendingTripID) } }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in loadLibrary(item) }
        .sheet(item: $draft) { draft in
            ParkCheckEditor(check: nil, photo: draft.photo, linkedDrive: drives.first { $0.id == draft.tripID }).presentationBackground(Lot.charcoal)
        }
        #if DEBUG
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            let args = CommandLine.arguments
            if args.contains("-showParkDetail"), let first = checks.first { path.append(first) }
            if args.contains("-newParkDraft"), let data = UIImage(systemName: "car.side")?.pngData() { draft = ParkDraft(photo: data) }
        }
        #endif
        .onChange(of: router.composingParkCheck, initial: true) { _, wanted in
            if wanted {
                wantsCamera = true
                pendingTripID = router.parkTripID
                router.parkTripID = nil
                showGate = true
                router.composingParkCheck = false
            }
        }
    }

    // MARK: Capture

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Lot.lime)
            VStack(alignment: .leading, spacing: 6) {
                Text("Photograph where you parked.")
                    .font(.system(size: 26, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                Text("Compare your attempts over time. Photos stay on this phone unless you ask for AI feedback.")
                    .font(LotType.body).foregroundStyle(Lot.muted)
            }
            HStack(spacing: 12) {
                Button { wantsCamera = true; showGate = true } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(LotButtonStyle(fullWidth: true))
                Button { wantsCamera = false; showGate = true } label: {
                    Label("Import", systemImage: "photo")
                }
                .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
            }
            Text(CameraPicker.isAvailable ? "Only when you're parked and out of the car." : "No camera on this device, so use Import.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Lot.charcoalRaised))
        .padding(.horizontal, Lot.Space.gutter)
    }

    private var emptyHistory: some View {
        LotEmptyState(symbol: "parkingsign.circle", title: "No parking checks yet",
                      message: "Your attempts will build a private history here, so you can see how parking gets easier.")
    }

    // MARK: Progress

    private var progress: some View {
        let stats = ProgressStats(trips: drives, checks: checks)
        let photoChecks = checks.filter { $0.photo != nil }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Progress").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                .padding(.horizontal, Lot.Space.gutter)

            if let first = photoChecks.last, let latest = photoChecks.first, first.id != latest.id {
                HStack(spacing: 12) {
                    thenNow(first, label: "First")
                    thenNow(latest, label: "Latest")
                }
                .padding(.horizontal, Lot.Space.gutter)
            }

            feedbackTrend

            Group {
                if let tries = stats.parkingTries {
                    Text("Your first checks took \(tries.early.formatted(.number.precision(.fractionLength(0...1)))) tries on average. Your latest took \(tries.recent.formatted(.number.precision(.fractionLength(0...1)))).")
                } else {
                    Text("Note how many tries each attempt took, and your trend shows up here. These are your own notes, not a score.")
                }
            }
            .font(LotType.caption).foregroundStyle(Lot.muted)
            .padding(.horizontal, Lot.Space.gutter)
        }
    }

    @ViewBuilder
    private var feedbackTrend: some View {
        let trend = ParkingFeedbackTrend(checks: checks)
        if trend.hasTrend {
            let shown = Array(trend.attempts.suffix(8))
            VStack(alignment: .leading, spacing: 12) {
                LotKicker(text: "AI feedback over time")
                ForEach(ParkingFeedbackTrend.aspects, id: \.self) { aspect in
                    HStack(spacing: 6) {
                        Text(aspect.title).font(LotType.caption).foregroundStyle(Lot.warmWhite)
                            .frame(width: 118, alignment: .leading)
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, attempt in
                            Image(systemName: Self.symbol(attempt.statuses[aspect] ?? .unclear))
                                .font(.system(size: 17))
                                .foregroundStyle(attempt.statuses[aspect] == .good ? Lot.lime : Lot.warmWhite.opacity(0.6))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(aspect.title), oldest to newest: " + shown.map { Self.word($0.statuses[aspect] ?? .unclear) }.joined(separator: ", "))
                }
                HStack {
                    Spacer().frame(width: 118)
                    Text("oldest").font(LotType.labelSmall).foregroundStyle(Lot.muted)
                    Spacer()
                    Text("latest").font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                if let summary = trend.summary {
                    Text(summary).font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.9))
                }
                Text("Checkmark: looked good. Half circle: okay. Arrows: needs work. Question mark: couldn't tell. This is not a score.")
                    .font(LotType.labelSmall).foregroundStyle(Lot.muted)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Lot.charcoalRaised))
            .padding(.horizontal, Lot.Space.gutter)
        }
    }

    private static func symbol(_ status: ParkingAnalysis.Status) -> String {
        switch status {
        case .good: "checkmark.circle.fill"
        case .okay: "circle.lefthalf.filled"
        case .needsWork: "arrow.triangle.2.circlepath"
        case .unclear: "questionmark.circle"
        }
    }

    private static func word(_ status: ParkingAnalysis.Status) -> String {
        switch status {
        case .good: "good"
        case .okay: "okay"
        case .needsWork: "needs work"
        case .unclear: "unclear"
        }
    }

    private func thenNow(_ check: ParkingCheck, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { ParkingImage(photo: check.photo) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(label).font(LotType.label).foregroundStyle(Lot.warmWhite)
            Text(check.date.formatted(.dateTime.month(.abbreviated).day())).font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History").font(LotType.headline).foregroundStyle(Lot.warmWhite)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(checks) { check in
                    NavigationLink(value: check) { ParkCell(check: check) }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Lot.Space.gutter)
    }

    private func loadLibrary(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let prepared = ImageTools.prepared(data) {
                draft = ParkDraft(photo: prepared, tripID: pendingTripID)
            }
            libraryItem = nil
        }
    }
}

/// Parking photo, or a neutral placeholder when the entry has none. Never generated art posing as a photo.
struct ParkingImage: View {
    let photo: Data?

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Lot.elevated
                Image(systemName: "parkingsign").font(.system(size: 34, weight: .light)).foregroundStyle(Lot.muted)
            }
        }
    }
}

private struct ParkCell: View {
    let check: ParkingCheck

    var body: some View {
        Color.clear
            .aspectRatio(0.85, contentMode: .fit)
            .overlay { ParkingImage(photo: check.photo) }
            .overlay {
                LinearGradient(colors: [.clear, Lot.charcoal.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) { if check.isDemo { DemoBadge().padding(10) } }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.maneuver.title).font(LotType.caption.weight(.semibold)).foregroundStyle(Lot.warmWhite)
                    Text(subtitle).font(LotType.labelSmall).foregroundStyle(Lot.warmWhite.opacity(0.8))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [check.date.formatted(.dateTime.month(.abbreviated).day())]
        if check.tries > 0 { parts.append(check.tries == 1 ? "1 try" : "\(check.tries) tries") }
        return parts.joined(separator: " · ")
    }
}
