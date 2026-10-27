import SwiftUI
import SwiftData

struct PlanDetailView: View {
    let plan: Plan
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedStopID: UUID?
    @State private var confirmDelete = false
    @State private var shareImage: UIImage?

    private var stops: [PlanStop] { plan.orderedStops }
    private var selectedStop: PlanStop? { stops.first { $0.id == selectedStopID } ?? stops.first }
    private var summary: PlanSummary { PlanSummary(plan: plan) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                itinerary
                if !plan.cars.isEmpty || !plan.people.isEmpty { rides }
                shareSection
            }
            .padding(.horizontal, Lot.Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .clearsTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .lotScreen()
        .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) {
                context.delete(plan)
                dismiss()
            }
        }
        .task(id: summary.text) {
            let renderer = ImageRenderer(content: PlanSummaryCard(summary: summary))
            renderer.scale = 3
            renderer.isOpaque = true
            shareImage = renderer.uiImage
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                LotCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Lot.warmWhite)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Lot.warmWhite.opacity(0.1)))
                }
                .accessibilityLabel("More")
            }
            VStack(alignment: .leading, spacing: 8) {
                if plan.isDemo { DemoBadge() }
                Text(plan.title).font(.system(size: 38, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                Text(plan.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(LotType.body).foregroundStyle(Lot.muted)
            }
        }
    }

    // MARK: Itinerary

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Itinerary").font(LotType.headline).foregroundStyle(Lot.warmWhite).padding(.bottom, 16)
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 16) {
                    Text(stop.time.formatted(.dateTime.hour().minute()))
                        .font(LotType.label).foregroundStyle(Lot.muted)
                        .frame(width: 66, alignment: .trailing)
                    VStack(spacing: 0) {
                        Circle().fill(index == 0 ? Lot.lime : Lot.warmWhite).frame(width: 10, height: 10).padding(.top, 4)
                        if index < stops.count - 1 {
                            Rectangle().fill(Lot.hairline).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    Text(stop.name).font(LotType.title).foregroundStyle(Lot.warmWhite)
                        .padding(.bottom, index < stops.count - 1 ? 22 : 0)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Rides

    private var rides: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rides").font(LotType.headline).foregroundStyle(Lot.warmWhite)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(stops) { stop in
                        LotToggleChip(text: stop.name, isOn: selectedStop?.id == stop.id) {
                            withAnimation(.snappy) { selectedStopID = stop.id }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let stop = selectedStop {
                Text("Who rides to \(stop.name)").font(LotType.caption).foregroundStyle(Lot.muted)

                ForEach(plan.orderedCars) { car in carBlock(car, stop) }

                if plan.cars.isEmpty {
                    Text("Add a driver in Edit to start assigning rides.").font(LotType.caption).foregroundStyle(Lot.muted)
                }

                needsRide(stop)

                if let index = stops.firstIndex(where: { $0.id == stop.id }), index > 0 {
                    Button {
                        withAnimation { plan.copyAssignments(from: stops[index - 1], to: stop, in: context) }
                    } label: {
                        Label("Copy rides from \(stops[index - 1].name)", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(LotButtonStyle(kind: .ghost))
                }

                Text("Check your state's passenger and license rules before offering rides. LOT doesn't verify them.")
                    .font(LotType.labelSmall).foregroundStyle(Lot.muted)
            }
        }
    }

    private func carBlock(_ car: PlanCar, _ stop: PlanStop) -> some View {
        let riders = plan.riders(in: car, at: stop)
        let left = plan.seatsLeft(in: car, at: stop)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(car.carName.isEmpty ? "\(car.driverName)'s car" : car.carName)
                        .font(LotType.title).foregroundStyle(Lot.warmWhite)
                    Text("\(car.driverName) driving").font(LotType.caption).foregroundStyle(Lot.muted)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<car.seats, id: \.self) { i in
                        Circle().fill(i < riders.count ? Lot.warmWhite : Lot.warmWhite.opacity(0.15)).frame(width: 10, height: 10)
                    }
                }
                .accessibilityLabel("\(riders.count) of \(car.seats) seats filled")
            }
            if riders.isEmpty {
                Text("No one yet").font(LotType.caption).foregroundStyle(Lot.muted)
            } else {
                FlowLayout { ForEach(riders) { person in personMenu(person, stop: stop, current: car) } }
            }
            if left == 0 { Text("Full").font(LotType.labelSmall).foregroundStyle(Lot.muted) }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Lot.charcoalRaised))
    }

    @ViewBuilder
    private func needsRide(_ stop: PlanStop) -> some View {
        let waiting = plan.unassigned(at: stop)
        if !plan.people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if waiting.isEmpty {
                    Label("Everyone has a ride", systemImage: "checkmark.circle.fill")
                        .font(LotType.body).foregroundStyle(Lot.lime)
                } else {
                    Label("\(waiting.count) still need\(waiting.count == 1 ? "s" : "") a ride", systemImage: "exclamationmark.triangle.fill")
                        .font(LotType.body.weight(.semibold)).foregroundStyle(Lot.warmWhite)
                    FlowLayout { ForEach(waiting) { person in personMenu(person, stop: stop, current: nil) } }
                }
            }
        }
    }

    private func personMenu(_ person: PlanPerson, stop: PlanStop, current: PlanCar?) -> some View {
        Menu {
            ForEach(plan.orderedCars.filter { $0.id != current?.id }) { car in
                rideButton(person, car: car, stop: stop)
            }
            if current != nil {
                Button(role: .destructive) {
                    withAnimation(.snappy) { plan.unassign(person, at: stop, in: context) }
                } label: {
                    Label("Needs a ride", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
        } label: {
            Text(person.name)
                .font(LotType.caption.weight(.medium))
                .foregroundStyle(current == nil ? Lot.charcoal : Lot.warmWhite)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(current == nil ? Lot.warmWhite : Lot.warmWhite.opacity(0.1)))
        }
        .accessibilityHint("Choose a ride")
    }

    private func rideButton(_ person: PlanPerson, car: PlanCar, stop: PlanStop) -> some View {
        let left = plan.seatsLeft(in: car, at: stop)
        let title: String = left > 0
            ? "Ride with \(car.driverName) · \(left) left"
            : "\(car.driverName)'s car is full"
        return Button(title) {
            withAnimation(.snappy) { _ = plan.assign(person, to: car, at: stop, in: context) }
        }
        .disabled(left == 0)
    }

    // MARK: Share

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage), preview: SharePreview("\(plan.title) plan", image: Image(uiImage: shareImage))) {
                    Label("Share Plan", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LotButtonStyle(fullWidth: true))
            }
            ShareLink(item: summary.text) {
                Label("Share as text", systemImage: "text.alignleft")
            }
            .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
            Text("Sharing sends a snapshot to your group chat. It won't update on other phones.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
    }
}

/// Shareable itinerary image. Fixed width, height grows with the plan.
struct PlanSummaryCard: View {
    let summary: PlanSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 3) {
                    Text("LOT").font(.system(size: 15, weight: .black)).foregroundStyle(Lot.warmWhite)
                    Circle().fill(Lot.lime).frame(width: 5, height: 5)
                }
                Spacer()
                if summary.isSample { Text("Sample plan").font(.system(size: 11, weight: .medium)).foregroundStyle(Lot.warmWhite.opacity(0.6)) }
            }
            Text(summary.title).font(.system(size: 36, weight: .heavy)).foregroundStyle(Lot.warmWhite).padding(.top, 28)
            Text(summary.dateText).font(.system(size: 15)).foregroundStyle(Lot.warmWhite.opacity(0.7)).padding(.top, 2)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(summary.stops) { stop in
                    HStack(alignment: .top, spacing: 14) {
                        Text(stop.time).font(.system(size: 13, weight: .semibold)).foregroundStyle(Lot.lime)
                            .frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Lot.warmWhite)
                            ForEach(stop.rides, id: \.self) { ride in
                                Text(ride).font(.system(size: 13)).foregroundStyle(Lot.warmWhite.opacity(0.75))
                            }
                            if !stop.needsRide.isEmpty {
                                Text("Needs a ride: \(stop.needsRide.joined(separator: ", "))")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Lot.warmWhite)
                            }
                        }
                    }
                }
            }
            .padding(.top, 28)
        }
        .padding(28)
        .frame(width: RecapMetrics.size.width, alignment: .leading)
        .background(
            ZStack {
                Lot.charcoal
                RadialGradient(colors: [Color(hex: 0x3F8F4E).opacity(0.25), .clear], center: .topTrailing, startRadius: 0, endRadius: 360)
            }
        )
    }
}
