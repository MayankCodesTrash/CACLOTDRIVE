import Foundation

enum TripFormat {
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(max(minutes, 1)) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Uses the user's regional road units (miles in the US).
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func dayAndTime(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) { return "Today, \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(time)"
    }

    static func timeOfDayTitle(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "Morning drive"
        case 11..<17: "Afternoon drive"
        case 17..<21: "Evening drive"
        default: "Night drive"
        }
    }
}
