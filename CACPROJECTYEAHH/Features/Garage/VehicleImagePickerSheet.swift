import SwiftUI
import PhotosUI

/// Lets the user swap the automatic match for another photo, one of their own, or the illustration.
struct VehicleImagePickerSheet: View {
    let car: Car

    @Environment(\.dismiss) private var dismiss
    @State private var store = VehicleImageStore.shared
    @State private var candidates: [VehicleImageCandidate] = []
    @State private var loading = true
    @State private var message: String?
    @State private var busy = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                Spacer()
                Text("Choose an image").font(LotType.title).foregroundStyle(Lot.warmWhite)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, Lot.Space.gutter)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Matches for \(VehicleQuery(car: car).displayName)")
                        .font(LotType.caption).foregroundStyle(Lot.muted)

                    if loading {
                        HStack(spacing: 10) { ProgressView().tint(Lot.warmWhite); Text("Searching…").font(LotType.caption).foregroundStyle(Lot.muted) }
                    } else if candidates.isEmpty {
                        Text(message ?? "No photos found. You can use one of your own, or the illustration.")
                            .font(LotType.caption).foregroundStyle(Lot.muted)
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(candidates) { candidate in
                                Button { choose(candidate) } label: { candidateCell(candidate) }
                                    .buttonStyle(.plain)
                                    .disabled(busy)
                            }
                        }
                    }

                    if let message, !candidates.isEmpty { Text(message).font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.85)) }

                    VStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Use my own photo", systemImage: "photo")
                        }
                        .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
                        .disabled(busy)

                        Button { store.useIllustration(for: car); dismiss() } label: {
                            Label("Use the illustration", systemImage: "car.side")
                        }
                        .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
                    }
                    if !WebImageSettings.shared.isActive {
                        Button { showSettings = true } label: {
                            Label("Search the web for real photos", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
                    }
                    Text("Web photos belong to their owners and stay in your own Garage. Wikimedia Commons photos keep their authors' credit. LOT cuts out the car on your phone, and a side-on photo of the whole car works best.")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                .padding(Lot.Space.gutter)
            }
            .scrollIndicators(.hidden)
        }
        .lotScreen()
        .overlay { if busy { busyOverlay } }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) { SettingsView().presentationBackground(Lot.charcoal) }
        .task { await load() }
        .onChange(of: photoItem) { _, item in pickOwn(item) }
    }

    private func candidateCell(_ candidate: VehicleImageCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1.4, contentMode: .fit)
                .overlay { VehicleThumbnail(candidate: candidate) }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(candidate.title).font(LotType.labelSmall).foregroundStyle(Lot.warmWhite).lineLimit(2)
            Text(candidate.isWebImage ? "Web · \(candidate.artist)" : "\(candidate.artist) · \(candidate.license)").font(.caption2).foregroundStyle(Lot.muted).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Use this photo")
    }

    private var busyOverlay: some View {
        ZStack {
            Lot.charcoal.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Lot.warmWhite)
                Text("Cutting out the car…").font(LotType.caption).foregroundStyle(Lot.warmWhite)
            }
        }
    }

    private func load() async {
        loading = true
        do { candidates = try await store.candidates(for: car) }
        catch { message = VehicleImageStore.message(for: error) }
        loading = false
    }

    private func choose(_ candidate: VehicleImageCandidate) {
        busy = true; message = nil
        Task {
            do { try await store.choose(candidate, for: car); dismiss() }
            catch { message = "That photo didn't work. Try another one." }
            busy = false
        }
    }

    private func pickOwn(_ item: PhotosPickerItem?) {
        guard let item else { return }
        busy = true; message = nil
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                do { try await store.useOwnPhoto(data, for: car); dismiss() }
                catch { message = "LOT couldn't separate the car from that photo. A side-on photo with a plain background works best." }
            }
            busy = false; photoItem = nil
        }
    }
}

/// Loads a small preview with the User-Agent Wikimedia asks for.
struct VehicleThumbnail: View {
    let candidate: VehicleImageCandidate
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Lot.charcoalRaised
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView().tint(Lot.muted) }
        }
        .task(id: candidate.id) {
            guard image == nil else { return }
            let small = candidate.previewURL
                ?? URL(string: candidate.imageURL.absoluteString.replacingOccurrences(of: "/1280px-", with: "/500px-"))
                ?? candidate.imageURL
            var request = URLRequest(url: small, timeoutInterval: 20)
            if !candidate.isWebImage { request.setValue(CommonsVehicleImageService.userAgent, forHTTPHeaderField: "User-Agent") }
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                image = UIImage(data: data)
            }
        }
    }
}
