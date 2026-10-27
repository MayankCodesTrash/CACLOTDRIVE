import Foundation

enum CarBodyStyle: String, CaseIterable, Identifiable {
    case sedan, hatchback, suv, pickup, coupe, van

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedan: "Sedan"
        case .hatchback: "Hatchback"
        case .suv: "SUV"
        case .pickup: "Pickup"
        case .coupe: "Coupe"
        case .van: "Van"
        }
    }
}
