import SwiftUI
import SwiftData

/// Add or edit a parking check. Every field is optional apart from the photo itself.
struct ParkCheckEditor: View {
    let check: ParkingCheck?
    /// The drive a new check is attached to, when it came from the end of a drive.
    var linkedDrive: Drive?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Car.createdAt) private var cars: [Car]

    @State private var photo: Data?
    @State private var maneuver: ParkingManeuver
    @State private var tries: Int
    @State private var tags: Set<ParkingTag>
    @State private var note: String
    @State private var car: Car?
    @State private var analysis: ParkingAnalysis?
    @State private var saved = false

    init(check: ParkingCheck?, photo: Data? = nil, linkedDrive: Drive? = nil) {
        self.check = check
        self.linkedDrive = linkedDrive
        _photo = State(initialValue: check?.photo ?? photo)
        _maneuver = State(initialValue: check?.maneuver ?? .straightIn)
        _tries = State(initialValue: check?.tries ?? 0)
        _tags = State(initialValue: Set(check?.tags ?? []))
        _note = State(initialValue: check?.note ?? "")
        _car = State(initialValue: check?.car)
        _analysis = State(initialValue: check?.aiAnalysis)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Color.clear
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay { ParkingImage(photo: photo) }
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    AIParkingSection(photo: photo, analysis: $analysis, onPhotoCovered: { covered in
                        photo = covered
                        // An already-saved check is updated right away so cancelling can't bring the original back.
                        check?.photo = covered
                    })

                    field("What kind of spot?") {
                        FlowLayout {
                            ForEach(ParkingManeuver.allCases) { option in
                                LotToggleChip(text: option.title, isOn: maneuver == option) { maneuver = option }
                            }
                        }
                    }

                    field("How many tries?") {
                        HStack(spacing: 10) {
                            ForEach(1...4, id: \.self) { value in
                                Button {
                                    withAnimation(.snappy) { tries = tries == value ? 0 : value }
                                } label: {
                                    Text(value == 4 ? "4+" : "\(value)")
                                        .font(LotType.numeral(18))
                                        .foregroundStyle(tries == value ? Lot.charcoal : Lot.warmWhite)
                                        .frame(width: 52, height: 52)
                                        .background(Circle().fill(tries == value ? Lot.warmWhite : Lot.warmWhite.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(value == 4 ? "4 or more tries" : "\(value) tries")
                            }
                        }
                    }

                    field("What did you notice?") {
                        FlowLayout {
                            ForEach(ParkingTag.allCases) { tag in
                                LotToggleChip(text: tag.title, isOn: tags.contains(tag)) {
                                    if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                                }
                            }
                        }
                    }

                    field("Note") {
                        TextField("", text: $note, prompt: Text("Anything to remember for next time?").foregroundStyle(Lot.muted), axis: .vertical)
                            .lineLimit(2...6)
                            .foregroundStyle(Lot.warmWhite)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lot.charcoalRaised))
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

                    Text("The photo stays on your phone unless you choose AI feedback. LOT itself never scores your parking.")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                .padding(Lot.Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lotScreen()
        .sensoryFeedback(.success, trigger: saved)
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
            Spacer()
            Text(check == nil ? "Park check" : "Edit check").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Spacer()
            Button("Save", action: save)
                .font(LotType.button).foregroundStyle(Lot.charcoal)
                .padding(.horizontal, 18).frame(minHeight: 44)
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

    private func save() {
        let target = check ?? ParkingCheck()
        if check == nil { context.insert(target); target.drive = linkedDrive }
        target.photo = photo
        target.aiAnalysis = analysis
        target.maneuver = maneuver
        target.tries = tries
        target.tags = ParkingTag.allCases.filter(tags.contains)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.car = car ?? (cars.count == 1 && check == nil ? cars.first : nil)
        saved.toggle()
        dismiss()
    }
}
