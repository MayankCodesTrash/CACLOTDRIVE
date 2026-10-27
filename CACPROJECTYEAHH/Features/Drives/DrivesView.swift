import SwiftUI
import SwiftData

private enum DriveEditorTarget: Identifiable {
    case new
    case edit(Drive)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let drive): drive.id.uuidString
        }
    }

    var drive: Drive? {
        if case .edit(let drive) = self { drive } else { nil }
    }
}

struct DrivesView: View {
    @Environment(LotRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Drive.date, order: .reverse) private var drives: [Drive]
    @State private var editor: DriveEditorTarget?
    @State private var recapTrip: Drive?
    @State private var path = NavigationPath()

    private var days: [(day: Date, trips: [Drive])] {
        let groups = Dictionary(grouping: drives) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    LotHeader(title: "Drives") {
                        Button { editor = .new } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Lot.warmWhite)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Lot.warmWhite.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a drive manually")
                    }

                    if drives.isEmpty {
                        LotEmptyState(symbol: "road.lanes", title: "No drives yet",
                                      message: "Drives you record or add will build a timeline here.",
                                      actionTitle: "Add a drive") { editor = .new }
                    } else {
                        NavigationLink(value: ProgressRoute.overview) {
                            HStack {
                                Label("Your progress", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(LotType.body.weight(.medium)).foregroundStyle(Lot.warmWhite)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal, Lot.Space.gutter)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, -12)

                        ForEach(days, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(dayTitle(group.day)).font(LotType.headline).foregroundStyle(Lot.warmWhite)
                                ForEach(group.trips) { trip in
                                    NavigationLink(value: trip) { DriveRow(drive: trip) }
                                        .buttonStyle(.plain)
                                        .contextMenu { menu(for: trip) }
                                }
                            }
                            .padding(.horizontal, Lot.Space.gutter)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .clearsTabBar()
            .navigationDestination(for: Drive.self) { TripDetailView(trip: $0) }
            .navigationDestination(for: ProgressRoute.self) { _ in ProgressOverviewView() }
            .toolbar(.hidden, for: .navigationBar)
            .lotScreen()
        }
        .sheet(item: $editor) { target in
            DriveEditor(drive: target.drive).presentationBackground(Lot.charcoal)
        }
        .sheet(item: $recapTrip) { trip in
            RecapSheet(trip: trip).presentationBackground(Lot.charcoal)
        }
        .onChange(of: router.composingDrive, initial: true) { _, wanted in
            if wanted {
                editor = .new
                router.composingDrive = false
            }
        }
    }

    @ViewBuilder
    private func menu(for trip: Drive) -> some View {
        Button("Share Recap", systemImage: "square.and.arrow.up") { recapTrip = trip }
        Button("Edit", systemImage: "pencil") { editor = .edit(trip) }
        Button(trip.isPassenger ? "Mark as my drive" : "Mark as passenger trip", systemImage: "person.2") {
            trip.isPassenger.toggle()
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            withAnimation { context.delete(trip) }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
