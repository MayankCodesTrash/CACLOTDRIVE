import SwiftUI
import SwiftData

private enum PlanEditorTarget: Identifiable {
    case new
    case edit(Plan)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let plan): plan.id.uuidString
        }
    }

    var plan: Plan? { if case .edit(let plan) = self { plan } else { nil } }
}

struct PlansView: View {
    @Query(sort: \Plan.date) private var plans: [Plan]
    @State private var editor: PlanEditorTarget?
    @State private var path = NavigationPath()

    private var upcoming: [Plan] { plans.filter { $0.date >= Calendar.current.startOfDay(for: .now) } }
    private var past: [Plan] { plans.filter { $0.date < Calendar.current.startOfDay(for: .now) }.reversed() }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    LotHeader(title: "Plans") {
                        Button { editor = .new } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Lot.warmWhite)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Lot.warmWhite.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Plan an outing")
                    }

                    if plans.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Plan the night, not another group chat.")
                                .font(.system(size: 28, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                            Text("Add your stops, who's driving, and who rides where. Then share the plan to the group chat you already use.")
                                .font(LotType.body).foregroundStyle(Lot.muted)
                            Button("Plan an outing") { editor = .new }.buttonStyle(LotButtonStyle())
                        }
                        .padding(.horizontal, Lot.Space.gutter)
                        .padding(.top, 8)
                    } else {
                        if !upcoming.isEmpty { section("Upcoming", upcoming) }
                        if !past.isEmpty { section("Past", past) }
                    }

                    Text("Plans live on this phone. Sharing sends a snapshot, and it won't update on anyone else's phone.")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                        .padding(.horizontal, Lot.Space.gutter)
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .clearsTabBar()
            .toolbar(.hidden, for: .navigationBar)
            .lotScreen()
            .navigationDestination(for: Plan.self) { plan in
                PlanDetailView(plan: plan) { editor = .edit(plan) }
            }
        }
        .sheet(item: $editor) { target in
            PlanEditor(plan: target.plan).presentationBackground(Lot.charcoal)
        }
        #if DEBUG
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            let args = CommandLine.arguments
            if args.contains("-showPlan"), let first = upcoming.first { path.append(first) }
            if args.contains("-editPlan"), let first = upcoming.first { editor = .edit(first) }
        }
        #endif
    }

    private func section(_ title: String, _ items: [Plan]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(LotType.headline).foregroundStyle(Lot.warmWhite)
            ForEach(items) { plan in
                NavigationLink(value: plan) { PlanRow(plan: plan) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Lot.Space.gutter)
    }
}

struct PlanRow: View {
    let plan: Plan

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                Text(plan.date.formatted(.dateTime.month(.abbreviated))).font(LotType.labelSmall).foregroundStyle(Lot.muted)
                Text(plan.date.formatted(.dateTime.day())).font(LotType.numeral(30)).foregroundStyle(Lot.warmWhite)
            }
            .frame(width: 64, height: 72)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Lot.charcoalRaised))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(plan.title).font(LotType.title).foregroundStyle(Lot.warmWhite).lineLimit(1)
                    if plan.isDemo { DemoBadge() }
                }
                Text(subtitle).font(LotType.caption).foregroundStyle(Lot.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [plan.orderedStops.first.map { $0.time.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? plan.date.formatted(.dateTime.weekday(.abbreviated))]
        parts.append("\(plan.stops.count) stop\(plan.stops.count == 1 ? "" : "s")")
        if let first = plan.orderedStops.first, plan.totalSeats > 0 {
            parts.append("\(plan.filledSeats(at: first)) of \(plan.totalSeats) seats")
        }
        return parts.joined(separator: " · ")
    }
}
