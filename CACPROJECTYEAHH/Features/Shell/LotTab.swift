import SwiftUI

enum LotTab: String, CaseIterable, Identifiable {
    case today, drives, park, plans, garage

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .today: "chart.xyaxis.line"
        case .drives: "book.closed"
        case .plans: "signpost.right.and.left"
        case .park: "parkingsign.circle"
        case .garage: "car.side"
        }
    }
}
