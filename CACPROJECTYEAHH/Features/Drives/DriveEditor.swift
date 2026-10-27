import SwiftUI
import SwiftData
import PhotosUI

/// Manual fallback for adding or editing a drive. Kept short on purpose:
/// everything beyond the basics lives under "More details".
struct DriveEditor: View {
    let drive: Drive?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Car.createdAt) private var cars: [Car]

    @State private var title: String
    @State private var date: Date
    @State private var minutes: Int
    @State private var notes: String
    @State private var car: Car?
    @State private var photos: [Data]
    @State private var skills: Set<Skill>
    @State private var confidence: Int
    @State private var showMore = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var saved = false

    private static let durations = [10, 15, 20, 30, 45, 60]
    private static let confidenceWords = ["Shaky", "Uneasy", "Okay", "Steady", "Confident"]

    init(drive: Drive?) {
        self.drive = drive
        _title = State(initialValue: drive?.title ?? "")
        _date = State(initialValue: drive?.date ?? .now)
        _minutes = State(initialValue: Int((drive?.durationSeconds ?? 0) / 60))
        _notes = State(initialValue: drive?.notes ?? "")
        _car = State(initialValue: drive?.car)
        _photos = State(initialValue: (drive?.photos.sorted { $0.order < $1.order }.map(\.data)) ?? [])
        _skills = State(initialValue: Set(drive?.skills ?? []))
        _confidence = State(initialValue: drive?.confidence ?? 0)
        _showMore = State(initialValue: !(drive?.skills.isEmpty ?? true) || (drive?.confidence ?? 0) > 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    field("Title") {
                        TextField("", text: $title, prompt: Text(TripFormat.timeOfDayTitle(for: date)).foregroundStyle(Lot.muted))
                            .font(LotType.headline)
                            .foregroundStyle(Lot.warmWhite)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) { Rectangle().fill(Lot.hairline).frame(height: 1) }
                    }

                    field("When") {
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(Lot.lime)
                            .colorScheme(.dark)
                    }

                    field("About how long?") {
                        FlowLayout {
                            ForEach(Self.durations, id: \.self) { value in
                                LotToggleChip(text: value == 60 ? "1 hr+" : "\(value) min", isOn: minutes == value) {
                                    minutes = minutes == value ? 0 : value
                                }
                            }
                        }
                    }

                    if !cars.isEmpty {
                        field("Car") {
                            FlowLayout {
                                LotToggleChip(text: "None", isOn: car == nil) { car = nil }
                                ForEach(cars) { option in
                                    LotToggleChip(text: option.nickname, symbol: "car.side", isOn: car == option) { car = option }
                                }
                            }
                        }
                    }

                    field("Notes") {
                        TextField("", text: $notes, prompt: Text("Anything worth remembering?").foregroundStyle(Lot.muted), axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundStyle(Lot.warmWhite)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
                    }

                    field("Photos") { photoSection }

                    moreDetails
                }
                .padding(Lot.Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lotScreen()
        .sensoryFeedback(.success, trigger: saved)
        .onChange(of: pickerItems) { _, items in loadPhotos(items) }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(LotType.caption.weight(.medium))
                .foregroundStyle(Lot.muted)
                .frame(minHeight: 44)
            Spacer()
            Text(drive == nil ? "Add a drive" : "Edit drive").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Spacer()
            Button("Save", action: save)
                .font(LotType.button)
                .foregroundStyle(Lot.charcoal)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(Lot.lime))
        }
        .padding(.horizontal, Lot.Space.gutter)
        .padding(.top, 16)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LotKicker(text: label)
            content()
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus").font(.title3)
                            Text("Add").font(LotType.labelSmall)
                        }
                        .foregroundStyle(Lot.warmWhite)
                        .frame(width: 92, height: 92)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Lot.charcoalRaised))
                    }
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Lot.warmWhite, Lot.charcoal.opacity(0.8))
                                            .font(.title3)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("Add photos after you've parked. Location data is removed from saved photos.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
    }

    private var moreDetails: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { withAnimation(.snappy) { showMore.toggle() } } label: {
                HStack {
                    Text("More details").font(LotType.body.weight(.medium)).foregroundStyle(Lot.warmWhite)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showMore ? 180 : 0)).foregroundStyle(Lot.muted)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if showMore {
                field("What did you practice?") {
                    FlowLayout {
                        ForEach(Skill.allCases) { skill in
                            LotToggleChip(text: skill.title, symbol: skill.symbol, isOn: skills.contains(skill)) {
                                if skills.contains(skill) { skills.remove(skill) } else { skills.insert(skill) }
                            }
                        }
                    }
                }
                field("How did it feel?") {
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                withAnimation(.snappy) { confidence = confidence == value ? 0 : value }
                            } label: {
                                Text("\(value)")
                                    .font(LotType.numeral(18))
                                    .foregroundStyle(value <= confidence ? Lot.charcoal : Lot.warmWhite)
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(value <= confidence ? Lot.warmWhite : Lot.warmWhite.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Confidence \(value) of 5")
                        }
                    }
                    Text(confidence > 0 ? Self.confidenceWords[confidence - 1] : "Optional")
                        .font(LotType.caption).foregroundStyle(Lot.muted)
                }
            }
        }
    }

    // MARK: Actions

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let prepared = ImageTools.prepared(data), photos.count < 6 {
                    photos.append(prepared)
                }
            }
            pickerItems = []
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? TripFormat.timeOfDayTitle(for: date) : trimmed

        let target = drive ?? Drive(title: finalTitle, scene: SceneStyle.forTime(date))
        if drive == nil { context.insert(target) }
        target.title = finalTitle
        target.date = date
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.skills = Skill.allCases.filter(skills.contains)
        target.confidence = confidence
        target.car = car
        if minutes > 0 {
            target.durationSeconds = Double(minutes) * 60
            target.endDate = date.addingTimeInterval(target.durationSeconds)
        }

        for old in target.photos { context.delete(old) }
        for (index, data) in photos.enumerated() {
            let photo = DrivePhoto(data: data, order: index)
            context.insert(photo)
            photo.drive = target
        }

        saved.toggle()
        dismiss()
    }
}
