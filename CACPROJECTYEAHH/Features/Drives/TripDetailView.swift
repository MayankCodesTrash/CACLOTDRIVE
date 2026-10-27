import SwiftUI
import SwiftData
import MapKit
import PhotosUI

struct TripDetailView: View {
    let trip: Drive

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var showRecap = false
    @State private var showMap = false
    @Environment(LotRouter.self) private var router
    @State private var confirmNotADrive = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewingPhoto: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                VStack(alignment: .leading, spacing: 32) {
                    if trip.needsReview { reviewCard }
                    stats
                    routePanel
                    photosSection
                    if let car = trip.car, !car.nickname.isEmpty { carRow(car) }
                    if !trip.notes.isEmpty { notes }
                    if !trip.skills.isEmpty { practiced }
                    parking

                    Button { showRecap = true } label: {
                        Label("Create Recap", systemImage: "sparkles")
                    }
                    .buttonStyle(LotButtonStyle(fullWidth: true))

                    Text(trip.source.title)
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                .padding(.horizontal, Lot.Space.gutter)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .clearsTabBar()
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .lotScreen()
        #if DEBUG
        .task {
            if CommandLine.arguments.contains("-showRouteMap") { try? await Task.sleep(for: .seconds(1)); showMap = true }
        }
        #endif
        .sheet(isPresented: $editing) { DriveEditor(drive: trip).presentationBackground(Lot.charcoal) }
        .fullScreenCover(isPresented: $showMap) {
            RouteMapScreen(title: trip.title, subtitle: mapSubtitle, points: trip.route, isSample: trip.isDemo)
        }
        .sheet(isPresented: $showRecap) { RecapSheet(trip: trip).presentationBackground(Lot.charcoal) }
        .confirmationDialog("Delete this drive?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete drive", role: .destructive) {
                context.delete(trip)
                dismiss()
            }
        } message: {
            Text("Its photos and notes will be removed from this phone.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        Color.clear
            .frame(height: 400)
            .overlay { cover }
            .overlay {
                LinearGradient(stops: [
                    .init(color: Lot.charcoal.opacity(0.6), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: Lot.charcoal, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                HStack {
                    LotCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                    Menu {
                        Button("Edit", systemImage: "pencil") { editing = true }
                        Button(trip.isPassenger ? "Mark as my drive" : "Mark as passenger trip", systemImage: "person.2") {
                            trip.isPassenger.toggle()
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
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
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if trip.isDemo { DemoBadge() }
                        if trip.isPassenger { LotChip(text: "Passenger", symbol: "person.2") }
                    }
                    Text(trip.title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Lot.warmWhite)
                    Text(trip.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        .font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.85))
                }
                .padding(Lot.Space.gutter)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var cover: some View {
        let photos = trip.photos.sorted { $0.order < $1.order }
        if photos.count > 1 {
            TabView {
                ForEach(photos) { photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image).resizable().scaledToFill().clipped()
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        } else {
            DriveArtwork(drive: trip)
        }
    }

    // MARK: Sections

    private var stats: some View {
        HStack(alignment: .top, spacing: 32) {
            if trip.durationSeconds > 0 { stat(TripFormat.duration(trip.durationSeconds), "Duration") }
            if let meters = trip.distanceMeters { stat(TripFormat.distance(meters), "Distance") }
            if let end = trip.endDate { stat(end.formatted(.dateTime.hour().minute()), "Arrived") }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Lot.warmWhite)
            Text(label).font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var routePanel: some View {
        if trip.route.count > 1 {
            Button { showMap = true } label: {
                RouteMapView(points: trip.route, isSample: trip.isDemo)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "map").font(.title2).foregroundStyle(Lot.muted)
                Text(trip.source == .manual
                     ? "No route for this drive. Drives you add by hand don't have one, but drives LOT detects do."
                     : "No route was recorded for this drive.")
                    .font(LotType.caption).foregroundStyle(Lot.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Lot.charcoalRaised))
        }
    }

    private var mapSubtitle: String {
        var parts = [trip.date.formatted(.dateTime.month(.abbreviated).day())]
        if trip.durationSeconds > 0 { parts.append(TripFormat.duration(trip.durationSeconds)) }
        if let meters = trip.distanceMeters { parts.append(TripFormat.distance(meters)) }
        return parts.joined(separator: " · ")
    }

    private func carRow(_ car: Car) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "car.side").foregroundStyle(Lot.muted)
            Text(car.nickname).font(LotType.title).foregroundStyle(Lot.warmWhite)
            if !car.model.isEmpty {
                Text(verbatim: "\(car.year) \(car.make) \(car.model)").font(LotType.caption).foregroundStyle(Lot.muted)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            LotKicker(text: "Notes")
            Text(trip.notes).font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.92))
        }
    }

    private var practiced: some View {
        VStack(alignment: .leading, spacing: 10) {
            LotKicker(text: "Practiced")
            FlowLayout { ForEach(trip.skills) { LotChip(text: $0.title, symbol: $0.symbol) } }
        }
    }

    private var parking: some View {
        VStack(alignment: .leading, spacing: 14) {
            LotKicker(text: "Parking")
            ForEach(trip.parkingChecks) { check in
                HStack(spacing: 14) {
                    Color.clear.frame(width: 56, height: 56)
                        .overlay { ParkingImage(photo: check.photo) }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.maneuver.title).font(LotType.title).foregroundStyle(Lot.warmWhite)
                        if let analysis = check.aiAnalysis, analysis.assessable {
                            Text(analysis.summary).font(LotType.caption).foregroundStyle(Lot.muted).lineLimit(2)
                        } else if !check.note.isEmpty {
                            Text(check.note).font(LotType.caption).foregroundStyle(Lot.muted)
                        }
                    }
                }
            }
            Button { router.startParkCheck(forTrip: trip.id) } label: {
                Label(trip.parkingChecks.isEmpty ? "Add a parking photo" : "Add another parking photo", systemImage: "camera")
            }
            .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
            Text("Only after you've parked and stepped out of the car.").font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
    }

    // MARK: Review

    /// LOT detects drives on its own and can't tell a driver from a passenger, so it asks.
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Was this you driving?").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Text("LOT notices trips by itself and can't tell a driver from a passenger. Your answer keeps your history accurate.")
                .font(LotType.caption).foregroundStyle(Lot.muted)
            HStack(spacing: 12) {
                Button("I was driving") { answer(.iDrove) }
                    .buttonStyle(LotButtonStyle(fullWidth: true))
                Button("Passenger") { answer(.passenger) }
                    .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
            }
            Button("This wasn't a drive. Delete it.") { confirmNotADrive = true }
                .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Lot.charcoalRaised))
        .confirmationDialog("Delete this trip?", isPresented: $confirmNotADrive, titleVisibility: .visible) {
            Button("Delete it", role: .destructive) {
                TripRepository(context: context).delete(trip)
                dismiss()
            }
        } message: {
            Text("Use this when LOT picked up something that wasn't a drive.")
        }
    }

    private func answer(_ answer: TripRepository.Review) {
        withAnimation(.smooth) { TripRepository(context: context).review(trip, as: answer) }
    }

    // MARK: Photos

    private var sortedPhotos: [DrivePhoto] { trip.photos.sorted { $0.order < $1.order } }

    /// Add as many photos as you like, any time after the drive.
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                Spacer()
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add", systemImage: "plus")
                        .font(LotType.label).foregroundStyle(Lot.charcoal)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Capsule().fill(Lot.warmWhite))
                }
                .accessibilityLabel("Add photos")
            }
            if sortedPhotos.isEmpty {
                Text("Add photos from this drive, after you've parked.").font(LotType.caption).foregroundStyle(Lot.muted)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(sortedPhotos.enumerated()), id: \.element.persistentModelID) { index, photo in
                            Button { viewingPhoto = index } label: {
                                if let image = UIImage(data: photo.data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 112, height: 112)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete photo", systemImage: "trash", role: .destructive) { delete(photo) } }
                            .accessibilityLabel("Photo \(index + 1) of \(sortedPhotos.count)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onChange(of: pickerItems) { _, items in addPhotos(items) }
        .fullScreenCover(item: $viewingPhoto) { index in
            PhotoViewer(photos: sortedPhotos, start: index) { delete($0) }
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var order = (trip.photos.map(\.order).max() ?? -1) + 1
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let prepared = ImageTools.prepared(data) {
                    let photo = DrivePhoto(data: prepared, order: order)
                    context.insert(photo)
                    photo.drive = trip
                    order += 1
                }
            }
            pickerItems = []
        }
    }

    private func delete(_ photo: DrivePhoto) {
        withAnimation { context.delete(photo) }
    }
}

extension Int: @retroactive Identifiable { public var id: Int { self } }

/// Full-screen photo pager for a drive.
private struct PhotoViewer: View {
    let photos: [DrivePhoto]
    let start: Int
    let onDelete: (DrivePhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(photos: [DrivePhoto], start: Int, onDelete: @escaping (DrivePhoto) -> Void) {
        self.photos = photos
        self.start = start
        self.onDelete = onDelete
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.persistentModelID) { i, photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image).resizable().scaledToFit().tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            HStack {
                LotCircleButton(symbol: "xmark", label: "Close") { dismiss() }
                Spacer()
                LotCircleButton(symbol: "trash", label: "Delete photo") {
                    guard photos.indices.contains(index) else { return }
                    let photo = photos[index]
                    if photos.count == 1 { dismiss() }
                    onDelete(photo)
                }
            }
            .padding(.horizontal, Lot.Space.gutter).padding(.top, 8)
        }
    }
}
