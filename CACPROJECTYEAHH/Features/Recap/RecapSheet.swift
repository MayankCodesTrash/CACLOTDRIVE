import SwiftUI
import PhotosUI

/// Pick a style, edit the caption, then share or save a real image of the recap.
struct RecapSheet: View {
    let trip: Drive

    @Environment(\.dismiss) private var dismiss
    @State private var style: RecapStyle = .night
    @State private var caption: String
    @State private var photoOverride: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var rendered: UIImage?

    init(trip: Drive) {
        self.trip = trip
        _caption = State(initialValue: trip.caption)
    }

    private var recapContent: RecapContent { RecapContent(trip: trip, photoOverride: photoOverride, caption: caption) }
    private var renderKey: String { "\(style.rawValue)|\(caption)|\(photoOverride?.count ?? 0)" }

    var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width - Lot.Space.gutter * 2)
        }
        .lotScreen()
        .task(id: renderKey) {
            rendered = RecapRenderer.image(style: style, content: recapContent)
        }
        .onChange(of: caption) { _, new in trip.caption = new }
        .onChange(of: pickerItem) { _, item in loadPhoto(item) }
    }

    private func content(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted)
                    .frame(minHeight: 44)
                Spacer()
                Text("Recap").font(LotType.title).foregroundStyle(Lot.warmWhite)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, Lot.Space.gutter)

            ScrollView {
                VStack(spacing: 24) {
                    preview(width: width)
                    stylePicker
                    controls
                }
                .padding(.horizontal, Lot.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            actions
        }
    }

    // MARK: Pieces

    private func preview(width: CGFloat) -> some View {
        let scale = min(1, width / RecapMetrics.size.width)
        return RecapCard(style: style, content: recapContent)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: RecapMetrics.size.width * scale, height: RecapMetrics.size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.25), value: style)
    }

    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(RecapStyle.allCases) { option in
                Button {
                    withAnimation(.snappy) { style = option }
                } label: {
                    Text(option.title)
                        .font(LotType.caption.weight(.semibold))
                        .foregroundStyle(style == option ? Lot.charcoal : Lot.warmWhite)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(style == option ? Lot.warmWhite : Lot.warmWhite.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(style == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: style)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("", text: $caption, prompt: Text("Add a caption (optional)").foregroundStyle(Lot.muted), axis: .vertical)
                .lineLimit(1...3)
                .foregroundStyle(Lot.warmWhite)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
                .onChange(of: caption) { _, new in if new.count > 90 { caption = String(new.prefix(90)) } }

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(photoOverride == nil && trip.photos.isEmpty ? "Add a photo" : "Change photo", systemImage: "photo")
                        .font(LotType.caption.weight(.medium))
                        .foregroundStyle(Lot.warmWhite)
                        .frame(minHeight: 44)
                }
                if photoOverride != nil {
                    Button("Use trip photo") { photoOverride = nil }
                        .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44).padding(.leading, 12)
                }
                Spacer()
            }
        }
    }

    private var actions: some View {
        RecapShareBar(image: rendered, title: "\(trip.title) recap", resetToken: renderKey)
    }

    // MARK: Actions

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoOverride = ImageTools.prepared(data)
            }
            pickerItem = nil
        }
    }
}

/// Share Recap and Save to Photos for any rendered recap image.
struct RecapShareBar: View {
    let image: UIImage?
    let title: String
    var resetToken: String = ""

    @State private var saveState: SaveState = .idle
    private enum SaveState { case idle, saving, saved, denied }

    var body: some View {
        VStack(spacing: 10) {
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                    Label("Share Recap", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LotButtonStyle(fullWidth: true))
            } else {
                Button { } label: { Label("Share Recap", systemImage: "square.and.arrow.up") }
                    .buttonStyle(LotButtonStyle(fullWidth: true))
                    .disabled(true)
            }

            Button(action: save) {
                Label(saveLabel, systemImage: saveState == .saved ? "checkmark" : "arrow.down.to.line")
            }
            .buttonStyle(LotButtonStyle(kind: .ghost, fullWidth: true))
            .disabled(image == nil || saveState == .saving)
            .sensoryFeedback(.success, trigger: saveState == .saved)

            if saveState == .denied {
                Text("Allow \"Add Photos Only\" for LOT in Settings to save recaps.")
                    .font(LotType.labelSmall).foregroundStyle(Lot.muted)
            }
        }
        .padding(.horizontal, Lot.Space.gutter)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(Lot.charcoal.opacity(0.92))
        .onChange(of: resetToken) { _, _ in saveState = .idle }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle, .denied: "Save to Photos"
        case .saving: "Saving…"
        case .saved: "Saved to Photos"
        }
    }

    private func save() {
        guard let image else { return }
        saveState = .saving
        Task { saveState = await PhotoSaver.save(image) ? .saved : .denied }
    }
}
