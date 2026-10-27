import SwiftUI
import SwiftData

private enum CarEditorTarget: Identifiable {
    case new
    case edit(Car)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let car): car.id.uuidString
        }
    }

    var car: Car? { if case .edit(let car) = self { car } else { nil } }
}

struct GarageView: View {
    @Query(sort: \Car.createdAt) private var cars: [Car]
    @Query private var drives: [Drive]
    @Query private var checks: [ParkingCheck]

    @State private var editor: CarEditorTarget?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    LotHeader(title: "Garage") {
                        Button { editor = .new } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Lot.warmWhite)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Lot.warmWhite.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a car")
                    }

                    if cars.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "car.side")
                                .font(.system(size: 56, weight: .light))
                                .foregroundStyle(Lot.warmWhite.opacity(0.8))
                            Text("Add your first car").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                            Text("Give it a nickname and a photo. Your drives and parking checks will connect to it.")
                                .font(LotType.caption).foregroundStyle(Lot.muted).multilineTextAlignment(.center)
                            Button("Add a car") { editor = .new }.buttonStyle(LotButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    } else {
                        VStack(spacing: 20) {
                            ForEach(cars) { car in
                                NavigationLink(value: car) { CarTile(car: car) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Lot.Space.gutter)

                        milestones
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .clearsTabBar()
            .toolbar(.hidden, for: .navigationBar)
            .lotScreen()
            .navigationDestination(for: Car.self) { car in
                CarDetailView(car: car) { editor = .edit(car) }
            }
            .navigationDestination(for: Drive.self) { TripDetailView(trip: $0) }
        }
        .sheet(item: $editor) { target in
            CarEditor(car: target.car).presentationBackground(Lot.charcoal)
        }
        .task(id: cars.map(\.id)) {
            for car in cars { await VehicleImageStore.shared.resolve(car) }
        }
        #if DEBUG
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            let args = CommandLine.arguments
            if args.contains("-savedAdjust"), let first = cars.first { first.garageAdjustment = GarageAdjustment(offsetX: -0.12, offsetY: 0.02, scale: 1.12) }
            if args.contains("-installCutout"), let first = cars.first {
                VehicleImageStore.shared.debugInstall(cutoutAt: NSTemporaryDirectory() + "cutout-test.png", for: first)
            }
            if args.contains("-showCar"), let first = cars.first { path.append(first) }
            if args.contains("-editCar") { editor = cars.first.map { .edit($0) } ?? .new }
        }
        #endif
    }

    private var milestones: some View {
        let stats = ProgressStats(trips: drives, checks: checks)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Milestones").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                Spacer()
                Text("\(stats.milestones.filter(\.earned).count) of \(stats.milestones.count)")
                    .font(LotType.label).foregroundStyle(Lot.muted)
            }
            .padding(.horizontal, Lot.Space.gutter)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(stats.milestones) { MilestoneBadge(milestone: $0) }
                }
                .padding(.horizontal, Lot.Space.gutter)
            }
            .scrollIndicators(.hidden)
            Text("Milestones come from reflecting and learning, never from how much or how fast you drive.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                .padding(.horizontal, Lot.Space.gutter)
        }
    }
}

private struct CarTile: View {
    let car: Car
    @State private var store = VehicleImageStore.shared

    var body: some View {
        Color.clear
            .aspectRatio(1.18, contentMode: .fit)
            .overlay { GarageSceneView(vehicle: store.image(for: car), isCutout: store.isCutout(car), bodyStyle: car.garageBodyStyle, adjustment: car.garageAdjustment) }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    if car.isDemo { DemoBadge() }
                    if case .working(let text) = store.state(for: car) {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini).tint(Lot.warmWhite); Text(text).font(LotType.labelSmall).foregroundStyle(Lot.warmWhite) }
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(Lot.charcoal.opacity(0.6)))
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(car.nickname).font(.system(size: 30, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                    if !car.model.isEmpty {
                        Text(verbatim: VehicleQuery(car: car).displayName).font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.85))
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct MilestoneBadge: View {
    let milestone: Milestone

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(milestone.earned ? Lot.lime.opacity(0.16) : .clear)
                Circle().stroke(Lot.hairline, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.001, milestone.progress))
                    .stroke(milestone.earned ? Lot.lime : Lot.warmWhite.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: milestone.symbol)
                    .font(.title3)
                    .foregroundStyle(milestone.earned ? Lot.lime : Lot.muted)
            }
            .frame(width: 70, height: 70)

            Text(milestone.title)
                .font(LotType.labelSmall.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Lot.warmWhite)
                .frame(width: 92)
            Text(milestone.earned ? "Earned" : milestone.detail)
                .font(LotType.labelSmall)
                .multilineTextAlignment(.center)
                .foregroundStyle(milestone.earned ? Lot.lime : Lot.muted)
                .frame(width: 92)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(milestone.title). \(milestone.detail). \(milestone.earned ? "Earned" : "\(Int(milestone.progress * 100)) percent")")
    }
}
