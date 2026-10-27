import SwiftUI
import SwiftData

private struct StopDraft: Identifiable {
    let id = UUID()
    var existing: PlanStop?
    var name = ""
    var time = Date()
}

private struct CarDraft: Identifiable {
    let id = UUID()
    var existing: PlanCar?
    var driver = ""
    var carName = ""
    var seats = 3
}

private struct PersonDraft: Identifiable {
    let id = UUID()
    var existing: PlanPerson?
    var name = ""
}

/// Create or edit an outing. Works on a draft, so Cancel never changes the saved plan.
struct PlanEditor: View {
    let plan: Plan?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Car.createdAt) private var garage: [Car]

    @State private var title: String
    @State private var day: Date
    @State private var stops: [StopDraft]
    @State private var cars: [CarDraft]
    @State private var people: [PersonDraft]
    @State private var newPerson = ""
    @State private var saved = false

    private static let stopSuggestions = ["Pictures", "Dinner", "Game", "Homecoming", "Movie", "Meetup"]

    init(plan: Plan?) {
        self.plan = plan
        _title = State(initialValue: plan?.title ?? "")
        _day = State(initialValue: plan?.date ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _stops = State(initialValue: plan?.orderedStops.map { StopDraft(existing: $0, name: $0.name, time: $0.time) } ?? [])
        _cars = State(initialValue: plan?.orderedCars.map { CarDraft(existing: $0, driver: $0.driverName, carName: $0.carName, seats: $0.seats) } ?? [])
        _people = State(initialValue: plan?.orderedPeople.map { PersonDraft(existing: $0, name: $0.name) } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    basics
                    stopsSection
                    carsSection
                    peopleSection
                }
                .padding(Lot.Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lotScreen()
        .sensoryFeedback(.success, trigger: saved)
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
            Spacer()
            Text(plan == nil ? "New plan" : "Edit plan").font(LotType.title).foregroundStyle(Lot.warmWhite)
            Spacer()
            Button("Save", action: save)
                .font(LotType.button).foregroundStyle(Lot.charcoal)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(Capsule().fill(Lot.lime))
        }
        .padding(.horizontal, Lot.Space.gutter)
        .padding(.top, 16)
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 24) {
            field("Name") {
                underlined("HOCO Night", text: $title, font: LotType.headline)
            }
            field("Day") {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .labelsHidden().tint(Lot.lime).colorScheme(.dark)
            }
        }
    }

    private var stopsSection: some View {
        field("Stops") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach($stops) { $stop in
                    let index = stops.firstIndex(where: { $0.id == stop.id }) ?? 0
                    HStack(spacing: 10) {
                        VStack(spacing: 0) {
                            iconButton("chevron.up", "Move up") { move(index, by: -1) }.disabled(index == 0)
                            iconButton("chevron.down", "Move down") { move(index, by: 1) }.disabled(index == stops.count - 1)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            underlined("Stop name", text: $stop.name)
                            DatePicker("Time", selection: $stop.time, displayedComponents: .hourAndMinute)
                                .labelsHidden().tint(Lot.lime).colorScheme(.dark)
                        }
                        iconButton("xmark", "Remove stop") { stops.removeAll { $0.id == stop.id } }
                    }
                }
                Text("Add a stop").font(LotType.labelSmall).foregroundStyle(Lot.muted)
                FlowLayout {
                    ForEach(Self.stopSuggestions, id: \.self) { name in
                        LotToggleChip(text: name, isOn: false) { addStop(name) }
                    }
                    LotToggleChip(text: "Custom", symbol: "plus", isOn: false) { addStop("") }
                }
            }
        }
    }

    private var carsSection: some View {
        field("Drivers and seats") {
            VStack(alignment: .leading, spacing: 20) {
                ForEach($cars) { $car in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            underlined("Driver", text: $car.driver)
                            iconButton("xmark", "Remove driver") { cars.removeAll { $0.id == car.id } }
                        }
                        underlined("Car (optional)", text: $car.carName)
                        HStack {
                            Text("Passenger seats").font(LotType.caption).foregroundStyle(Lot.muted)
                            Spacer()
                            iconButton("minus", "Fewer seats") { car.seats = max(1, car.seats - 1) }
                            Text("\(car.seats)").font(LotType.numeral(22)).foregroundStyle(Lot.warmWhite).frame(minWidth: 28)
                            iconButton("plus", "More seats") { car.seats = min(7, car.seats + 1) }
                        }
                    }
                }
                HStack(spacing: 8) {
                    LotToggleChip(text: "Add a driver", symbol: "plus", isOn: false) { cars.append(CarDraft()) }
                    ForEach(garage.filter { garageCar in !cars.contains { $0.carName == garageCar.nickname } }) { garageCar in
                        LotToggleChip(text: garageCar.nickname, symbol: "car.side", isOn: false) {
                            cars.append(CarDraft(carName: garageCar.nickname))
                        }
                    }
                }
                Text("Seats don't include the driver. Check your state's passenger and license rules before offering rides.")
                    .font(LotType.labelSmall).foregroundStyle(Lot.muted)
            }
        }
    }

    private var peopleSection: some View {
        field("Riders") {
            VStack(alignment: .leading, spacing: 14) {
                if !people.isEmpty {
                    FlowLayout {
                        ForEach(people) { person in
                            Button { people.removeAll { $0.id == person.id } } label: {
                                HStack(spacing: 6) {
                                    Text(person.name)
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                }
                                .font(LotType.caption.weight(.medium))
                                .foregroundStyle(Lot.warmWhite)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Capsule().fill(Lot.warmWhite.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(person.name)")
                        }
                    }
                }
                HStack {
                    underlined("Add a rider", text: $newPerson)
                        .onSubmit(addPerson)
                        .submitLabel(.done)
                    Button("Add", action: addPerson)
                        .font(LotType.button).foregroundStyle(Lot.warmWhite).frame(minWidth: 44, minHeight: 44)
                        .disabled(newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: Helpers

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LotKicker(text: label)
            content()
        }
    }

    private func underlined(_ prompt: String, text: Binding<String>, font: Font = LotType.body) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Lot.muted))
            .font(font)
            .foregroundStyle(Lot.warmWhite)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Lot.hairline).frame(height: 1) }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Lot.warmWhite)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func addStop(_ name: String) {
        let base = stops.last?.time ?? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
        let next = stops.isEmpty ? base : base.addingTimeInterval(60 * 75)
        withAnimation(.snappy) { stops.append(StopDraft(name: name, time: next)) }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard stops.indices.contains(target) else { return }
        withAnimation(.snappy) { stops.swapAt(index, target) }
    }

    private func addPerson() {
        let name = newPerson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        people.append(PersonDraft(name: name))
        newPerson = ""
    }

    // MARK: Save

    private func save() {
        let cal = Calendar.current
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = plan ?? Plan(title: name.isEmpty ? "Outing" : name, date: day)
        if plan == nil { context.insert(target) }
        target.title = name.isEmpty ? "Outing" : name

        func onDay(_ time: Date) -> Date {
            let parts = cal.dateComponents([.hour, .minute], from: time)
            return cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? time
        }

        let keptStops = Set(stops.compactMap { $0.existing?.id })
        for old in target.stops where !keptStops.contains(old.id) { context.delete(old) }
        for (index, draft) in stops.enumerated() {
            let stop = draft.existing ?? PlanStop(order: index, name: draft.name, time: onDay(draft.time))
            if draft.existing == nil { context.insert(stop); stop.plan = target }
            stop.order = index
            stop.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Stop \(index + 1)" : draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            stop.time = onDay(draft.time)
        }

        let keptCars = Set(cars.compactMap { $0.existing?.id })
        for old in target.cars where !keptCars.contains(old.id) { context.delete(old) }
        for (index, draft) in cars.enumerated() {
            let car = draft.existing ?? PlanCar(order: index, driverName: draft.driver, carName: draft.carName, seats: draft.seats)
            if draft.existing == nil { context.insert(car); car.plan = target }
            car.order = index
            car.driverName = draft.driver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Driver \(index + 1)" : draft.driver.trimmingCharacters(in: .whitespacesAndNewlines)
            car.carName = draft.carName.trimmingCharacters(in: .whitespacesAndNewlines)
            car.seats = draft.seats
        }

        let keptPeople = Set(people.compactMap { $0.existing?.id })
        for old in target.people where !keptPeople.contains(old.id) { context.delete(old) }
        for (index, draft) in people.enumerated() {
            let person = draft.existing ?? PlanPerson(order: index, name: draft.name)
            if draft.existing == nil { context.insert(person); person.plan = target }
            person.order = index
            person.name = draft.name
        }

        target.date = target.orderedStops.first?.time ?? day
        target.trimOverCapacity(in: context)
        saved.toggle()
        dismiss()
    }
}
