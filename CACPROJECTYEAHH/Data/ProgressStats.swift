import Foundation

struct SkillCount: Identifiable {
    let skill: Skill
    let count: Int
    var id: String { skill.id }
}

struct Milestone: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Double

    var earned: Bool { progress >= 1 }
}

/// Plain counts of what the user has recorded. These describe activity, not driving quality,
/// and deliberately avoid scores or "safer driver" implications.
struct ProgressStats {
    let tripCount: Int
    let parkingCheckCount: Int
    let reflectionCount: Int
    let practiced: [SkillCount]
    let firstTripDate: Date?
    /// Average tries per parking attempt: earliest checks vs. most recent, from what the user recorded.
    let parkingTries: (early: Double, recent: Double)?
    let milestones: [Milestone]

    init(trips: [Drive], checks: [ParkingCheck]) {
        let own = trips.filter { !$0.isPassenger }
        tripCount = own.count
        parkingCheckCount = checks.count
        reflectionCount = own.filter { !$0.notes.trimmingCharacters(in: .whitespaces).isEmpty }.count
        practiced = Dictionary(grouping: own.flatMap(\.skills), by: { $0 })
            .map { SkillCount(skill: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.skill.title) > ($1.count, $0.skill.title) }
        firstTripDate = own.map(\.date).min()

        let withTries = checks.filter { $0.tries > 0 }.sorted { $0.date < $1.date }
        if withTries.count >= 4 {
            let k = min(3, withTries.count / 2)
            func avg(_ slice: ArraySlice<ParkingCheck>) -> Double { Double(slice.map(\.tries).reduce(0, +)) / Double(slice.count) }
            parkingTries = (avg(withTries.prefix(k)), avg(withTries.suffix(k)))
        } else {
            parkingTries = nil
        }

        let photoTrips = own.filter { !$0.photos.isEmpty }.count
        let improved = parkingTries.map { $0.recent < $0.early } ?? false
        milestones = [
            Milestone(id: "first", title: "First drive saved", detail: "Save your first drive", symbol: "flag.checkered",
                      progress: min(1, Double(own.count))),
            Milestone(id: "park1", title: "First park check", detail: "Save a parking photo", symbol: "parkingsign",
                      progress: min(1, Double(checks.count))),
            Milestone(id: "notes", title: "Thoughtful driver", detail: "Write notes on 5 drives", symbol: "text.bubble",
                      progress: min(1, Double(own.filter { !$0.notes.trimmingCharacters(in: .whitespaces).isEmpty }.count) / 5)),
            Milestone(id: "photos", title: "Memory maker", detail: "Add photos to 3 drives", symbol: "photo.on.rectangle",
                      progress: min(1, Double(photoTrips) / 3)),
            Milestone(id: "situations", title: "Well-rounded", detail: "Practice 5 different situations", symbol: "square.grid.2x2",
                      progress: min(1, Double(Set(own.flatMap(\.skills)).count) / 5)),
            Milestone(id: "tries", title: "Fewer tries", detail: "Park in fewer tries than when you started",
                      symbol: "arrow.down.right", progress: improved ? 1 : min(0.9, Double(withTries.count) / 6)),
        ]
    }
}


/// How the AI's qualitative statuses changed across parking checks. Built only from feedback already saved
/// on the checks. It counts statuses, it never invents a score.
struct ParkingFeedbackTrend: Equatable {
    struct Attempt: Equatable {
        let date: Date
        let statuses: [ParkingAnalysis.Aspect: ParkingAnalysis.Status]
        var judged: Int { statuses.values.filter { $0 != .unclear }.count }
        var good: Int { statuses.values.filter { $0 == .good }.count }
    }

    let attempts: [Attempt]

    static let aspects: [ParkingAnalysis.Aspect] = [.inLines, .centering, .straightness]

    init(checks: [ParkingCheck]) {
        attempts = checks
            .compactMap { check -> Attempt? in
                guard let analysis = check.aiAnalysis, analysis.assessable else { return nil }
                return Attempt(date: check.date, statuses: Dictionary(analysis.findings.map { ($0.aspect, $0.status) }, uniquingKeysWith: { first, _ in first }))
            }
            .sorted { $0.date < $1.date }
    }

    /// A grid needs at least two reviewed photos to show change.
    var hasTrend: Bool { attempts.count >= 2 }

    /// "In your first 3 reviewed photos, 4 of 9 areas looked good. In your latest 3: 8 of 9."
    var summary: String? {
        guard hasTrend else { return nil }
        let k = min(3, attempts.count / 2)
        func tally(_ slice: ArraySlice<Attempt>) -> (good: Int, judged: Int) {
            (slice.map(\.good).reduce(0, +), slice.map(\.judged).reduce(0, +))
        }
        let early = tally(attempts.prefix(k)), recent = tally(attempts.suffix(k))
        guard early.judged > 0, recent.judged > 0 else { return nil }
        let noun = k == 1 ? "photo" : "photos"
        return "In your first \(k) reviewed \(noun), \(early.good) of \(early.judged) areas looked good. In your latest \(k): \(recent.good) of \(recent.judged)."
    }
}
