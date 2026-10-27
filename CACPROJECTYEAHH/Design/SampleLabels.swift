import SwiftUI

/// Whether sample items wear a "Sample" label. Off by default so recordings and screenshots look clean.
/// The sample data itself is still removable from Settings, and its records are still flagged internally.
enum SampleLabels {
    static let key = "lot.showSampleLabels"

    static var isVisible: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
}

extension View {
    /// Leaves room at the bottom of a scroll view for the floating tab bar, so nothing is hidden behind it.
    func clearsTabBar() -> some View {
        contentMargins(.bottom, Lot.Space.tabBarClearance, for: .scrollContent)
    }
}
