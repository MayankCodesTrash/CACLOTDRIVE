import SwiftUI
import SwiftData

struct CarDetailView: View {
    let car: Car
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = VehicleImageStore.shared
    @State private var confirmDelete = false
    @State private var choosing = false
    @State private var shareItems: [Any]?
    @State private var isAdjusting = false
    @State private var draft = GarageAdjustment.neutral
    @State private var dragStart: GarageAdjustment?
    @State private var pinchStart: CGFloat?
    @State private var heroSize = CGSize(width: 393, height: 460)

    private var drives: [Drive] { car.drives.sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    credit
                    HStack(alignment: .top, spacing: 32) {
                        stat("\(car.drives.filter { !$0.isPassenger }.count)", "Drives")
                        stat("\(car.parkingChecks.count)", "Parking checks")
                        stat(car.createdAt.formatted(.dateTime.month(.abbreviated).year()), "In your garage")
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Drives in \(car.nickname)").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                        if drives.isEmpty {
                            Text("Drives you save with this car appear here.").font(LotType.caption).foregroundStyle(Lot.muted)
                        } else {
                            ForEach(drives) { drive in
                                NavigationLink(value: drive) { DriveRow(drive: drive) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, Lot.Space.gutter)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .clearsTabBar()
        .scrollDisabled(isAdjusting)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .lotScreen()
        .task { await store.resolve(car) }
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("-adjustCar") {
                try? await Task.sleep(for: .seconds(1.5))
                startAdjusting()
                draft = GarageAdjustment(offsetX: 0.14, offsetY: -0.06, scale: 1.3)
            }
        }
        .task {
            if CommandLine.arguments.contains("-showImagePicker") { try? await Task.sleep(for: .seconds(1)); choosing = true }
        }
        .task {
            guard CommandLine.arguments.contains("-dumpGarage") else { return }
            try? await Task.sleep(for: .seconds(2))
            let content = GarageShareCard(car: car, vehicle: store.image(for: car), credit: store.credit(for: car), isCutout: store.isCutout(car))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("garage-dump.png"))
            }
        }
        #endif
        .sheet(isPresented: $choosing) { VehicleImagePickerSheet(car: car).presentationBackground(Lot.charcoal) }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let shareItems { ActivityView(items: shareItems).presentationDetents([.medium, .large]) }
        }
        .confirmationDialog("Remove \(car.nickname)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove car", role: .destructive) {
                store.forget(car)
                context.delete(car)
                dismiss()
            }
        } message: {
            Text("Your drives and parking checks stay. They just won't be linked to a car.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        Color.clear
            .frame(height: 460)
            .overlay {
                GarageSceneView(vehicle: store.image(for: car), isCutout: store.isCutout(car), bodyStyle: car.garageBodyStyle,
                                adjustment: isAdjusting ? draft : car.garageAdjustment, showsAdjustOutline: isAdjusting)
            }
            .overlay { if isAdjusting { adjustSurface } }
            .overlay(alignment: .top) {
                if isAdjusting {
                    HStack {
                        Button("Reset") { withAnimation(.smooth) { draft = .neutral } }
                            .buttonStyle(LotButtonStyle(kind: .ghost))
                        Spacer()
                        Button("Done") {
                            car.garageAdjustment = draft
                            withAnimation(.smooth) { isAdjusting = false }
                        }
                        .buttonStyle(LotButtonStyle())
                    }
                    .padding(.horizontal, Lot.Space.gutter)
                    .padding(.top, 58)
                } else {
                HStack {
                    LotCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                    Menu {
                        Button("Edit", systemImage: "pencil", action: onEdit)
                        Button("Choose another image", systemImage: "photo.on.rectangle") { choosing = true }
                        if store.isCutout(car) {
                            Button("Move the car in the garage", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { startAdjusting() }
                        } else {
                            Button("Moving the car needs a cutout", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {}.disabled(true)
                        }
                        if store.credit(for: car)?.isWebImage == true {
                            Button("Sharing isn't available for web photos", systemImage: "square.and.arrow.up") {}.disabled(true)
                        } else {
                            Button("Share garage image", systemImage: "square.and.arrow.up") { shareGarageImage() }
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Lot.warmWhite)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Lot.charcoal.opacity(0.55)))
                    }
                    .accessibilityLabel("More")
                }
                .padding(.horizontal, Lot.Space.gutter)
                .padding(.top, 58)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isAdjusting {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drag to move · pinch or use the slider to resize")
                            .font(LotType.labelSmall).foregroundStyle(Lot.warmWhite)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Lot.charcoal.opacity(0.7)))
                            .allowsHitTesting(false)
                        resizeBar
                    }
                    .padding(Lot.Space.gutter)
                } else {
                VStack(alignment: .leading, spacing: 6) {
                    if car.isDemo { DemoBadge() }
                    Text(car.nickname).font(.system(size: 38, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                    if !car.model.isEmpty {
                        Text(verbatim: VehicleQuery(car: car).displayName).font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.85))
                    }
                }
                .padding(Lot.Space.gutter)
                .allowsHitTesting(false)
                }
            }
    }

    // MARK: Moving the car

    private func startAdjusting() {
        draft = car.garageAdjustment
        withAnimation(.smooth) { isAdjusting = true }
    }

    /// What the layout will really allow, so the car never gets dragged somewhere it can't be.
    private func limited(_ proposed: GarageAdjustment, in size: CGSize) -> GarageAdjustment {
        let analysis = VehicleGeometryAnalyzer.cachedAnalysis(of: store.image(for: car) ?? UIImage())
        return GarageLayout(size: size, analysis: analysis, bodyHeight: car.garageBodyStyle.realHeightMeters, adjustment: proposed).appliedAdjustment
    }

    private var adjustSurface: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onAppear { heroSize = geo.size }
                .onChange(of: geo.size) { _, new in heroSize = new }
                .gesture(moveGesture(in: geo.size))
                .simultaneousGesture(pinchGesture(in: geo.size))
                .modifier(AdjustAccessibility(
                    move: { dx, dy in nudge(dx: dx, dy: dy, in: geo.size) },
                    resize: { factor in resize(to: draft.scale * factor, in: geo.size) }))
        }
    }

    /// Dragging moves the car, sideways and up and down, like moving a photo.
    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? draft
                dragStart = start
                let proposed = GarageAdjustment(offsetX: start.offsetX + value.translation.width / size.width,
                                                offsetY: start.offsetY + value.translation.height / size.height,
                                                scale: start.scale)
                draft = limited(proposed, in: size)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Pinching resizes the car in place.
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? draft.scale
                pinchStart = start
                resize(to: start * value.magnification, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func resize(to scale: CGFloat, in size: CGSize) {
        draft = limited(GarageAdjustment(offsetX: draft.offsetX, offsetY: draft.offsetY, scale: scale), in: size)
    }

    private func nudge(dx: CGFloat, dy: CGFloat, in size: CGSize) {
        draft = limited(GarageAdjustment(offsetX: draft.offsetX + dx, offsetY: draft.offsetY + dy, scale: draft.scale), in: size)
    }

    /// A slider for resizing, so it works without a pinch (and in the simulator).
    private var resizeBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(Lot.warmWhite)
            Slider(value: Binding(get: { Double(draft.scale) },
                                  set: { resize(to: CGFloat($0), in: heroSize) }),
                   in: Double(GarageAdjustment.scaleRange.lowerBound)...Double(GarageAdjustment.scaleRange.upperBound))
                .tint(Lot.lime)
                .accessibilityLabel("Car size")
            Image(systemName: "plus.magnifyingglass").foregroundStyle(Lot.warmWhite)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Capsule().fill(Lot.charcoal.opacity(0.7)))
    }

    // MARK: Credit and status

    @ViewBuilder
    private var credit: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.state(for: car) {
            case .working(let text):
                HStack(spacing: 10) { ProgressView().tint(Lot.warmWhite); Text(text).font(LotType.caption).foregroundStyle(Lot.muted) }
            case .photo:
                if let candidate = store.credit(for: car) {
                    Text(candidate.isWebImage
                         ? "Web photo from \(candidate.artist) · © its owner. Kept in your Garage only."
                         : "Photo: \(candidate.artist) · \(candidate.license) · \(candidate.provider)")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                    if let page = candidate.pageURL { Link("View original", destination: page).font(LotType.labelSmall).foregroundStyle(Lot.warmWhite) }
                } else {
                    Text("Using your own photo.").font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                if !store.isCutout(car) {
                    Text("LOT couldn't remove this photo's background, so it's shown as is. Another image may look cleaner.")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
            case .demo(let reason):
                Text(reason ?? "Showing an illustration of a \(car.bodyStyle.title.lowercased()), not your exact car.")
                    .font(LotType.labelSmall).foregroundStyle(Lot.muted)
            case .idle:
                EmptyView()
            }
            Button { choosing = true } label: {
                Label("Not your car? Choose another image", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(LotButtonStyle(kind: .ghost))
        }
    }

    // MARK: Sharing

    /// Renders the garage scene with the photo credit baked in, since Creative Commons photos must be credited.
    private func shareGarageImage() {
        let content = GarageShareCard(car: car, vehicle: store.image(for: car), credit: store.credit(for: car), isCutout: store.isCutout(car))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = true
        if let image = renderer.uiImage { shareItems = [image] }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Lot.warmWhite)
            Text(label).font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GarageShareCard: View {
    let car: Car
    let vehicle: UIImage?
    let credit: VehicleImageCandidate?
    var isCutout = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GarageSceneView(vehicle: vehicle, isCutout: isCutout, bodyStyle: car.garageBodyStyle, adjustment: car.garageAdjustment)
            LinearGradient(colors: [.clear, Lot.charcoal.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(car.nickname).font(.system(size: 36, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                Text(verbatim: VehicleQuery(car: car).displayName).font(.system(size: 15)).foregroundStyle(Lot.warmWhite.opacity(0.85))
                Text(credit.map { "Photo: \($0.artist) · \($0.license) · \($0.provider)" } ?? (car.isDemo && SampleLabels.isVisible ? "Sample data · Made with LOT" : "Made with LOT"))
                    .font(.system(size: 10)).foregroundStyle(Lot.warmWhite.opacity(0.6)).lineLimit(2).padding(.top, 4)
            }
            .padding(22)
        }
        .frame(width: 360, height: 360)
    }
}

/// VoiceOver actions for moving and resizing the car without gestures.
private struct AdjustAccessibility: ViewModifier {
    let move: (CGFloat, CGFloat) -> Void
    let resize: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Car position and size")
            .accessibilityHint("Use the actions to move or resize the car")
            .accessibilityAction(named: "Move left") { move(-0.05, 0) }
            .accessibilityAction(named: "Move right") { move(0.05, 0) }
            .accessibilityAction(named: "Move up") { move(0, -0.04) }
            .accessibilityAction(named: "Move down") { move(0, 0.04) }
            .accessibilityAction(named: "Make larger") { resize(1.08) }
            .accessibilityAction(named: "Make smaller") { resize(1 / 1.08) }
    }
}
