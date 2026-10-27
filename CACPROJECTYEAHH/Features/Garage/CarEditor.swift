import SwiftUI
import SwiftData

/// Tell LOT about your car. It finds a picture for you, so there's nothing to upload.
struct CarEditor: View {
    let car: Car?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var nickname: String
    @State private var make: String
    @State private var model: String
    @State private var trim: String
    @State private var year: Int
    @State private var colorHex: String
    @State private var saved = false

    private static let currentYear = Calendar.current.component(.year, from: .now)

    init(car: Car?) {
        self.car = car
        _nickname = State(initialValue: car?.nickname ?? "")
        _make = State(initialValue: car?.make ?? "")
        _model = State(initialValue: car?.model ?? "")
        _trim = State(initialValue: car?.trim ?? "")
        _year = State(initialValue: car?.year ?? 2012)
        _colorHex = State(initialValue: car?.colorHex ?? "F2F2EF")
    }

    private var previewBody: CarBodyStyle { CarBodyHints.guess(make: make, model: model) ?? car?.bodyStyle ?? .sedan }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    GarageSceneView(vehicle: DemoVehicleLibrary.image(body: previewBody, colorHex: colorHex), bodyStyle: previewBody)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(alignment: .topLeading) { DemoBadge().padding(14) }

                    field("Nickname") { underlined("Biscuit", text: $nickname, font: LotType.headline) }

                    field("Year") {
                        HStack(spacing: 20) {
                            stepper("minus") { year = max(1980, year - 1) }
                            Text(verbatim: "\(year)").font(LotType.numeral(28)).foregroundStyle(Lot.warmWhite).frame(minWidth: 80)
                            stepper("plus") { year = min(Self.currentYear + 1, year + 1) }
                        }
                    }

                    field("Make and model") {
                        HStack(spacing: 16) {
                            underlined("Honda", text: $make)
                            underlined("Civic", text: $model)
                        }
                    }

                    field("Trim (optional)") { underlined("EX, Sport, LX…", text: $trim) }

                    field("Color") {
                        FlowLayout(spacing: 12) {
                            ForEach(CarPalette.swatches, id: \.hex) { swatch in
                                Button { colorHex = swatch.hex } label: {
                                    Circle().fill(Color(hexString: swatch.hex))
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().strokeBorder(Lot.hairline, lineWidth: 1))
                                        .overlay(Circle().strokeBorder(Lot.warmWhite, lineWidth: colorHex == swatch.hex ? 3 : 0).padding(-4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(swatch.name)
                                .accessibilityAddTraits(colorHex == swatch.hex ? .isSelected : [])
                            }
                        }
                    }

                    Text("LOT looks for a photo of your car using only the year, make, model and trim you enter, and cuts out the background on your phone. Offline, or if nothing matches, you'll see an illustration that you can swap for another image.")
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
            Text(car == nil ? "Add a car" : "Edit car").font(LotType.title).foregroundStyle(Lot.warmWhite)
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

    private func underlined(_ prompt: String, text: Binding<String>, font: Font = LotType.title) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Lot.muted))
            .font(font)
            .foregroundStyle(Lot.warmWhite)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Lot.hairline).frame(height: 1) }
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Lot.warmWhite)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Lot.warmWhite.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Later year" : "Earlier year")
    }

    private func save() {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = car ?? Car(nickname: name)
        if car == nil { context.insert(target) }
        let before = VehicleQuery(car: target).signature
        target.nickname = name.isEmpty ? "My car" : name
        target.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        target.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        target.trim = trim.trimmingCharacters(in: .whitespacesAndNewlines)
        target.year = year
        target.colorHex = colorHex
        target.bodyStyle = previewBody
        let changed = car == nil || before != VehicleQuery(car: target).signature
        saved.toggle()
        dismiss()
        Task { await VehicleImageStore.shared.resolve(target, force: changed) }
    }
}
