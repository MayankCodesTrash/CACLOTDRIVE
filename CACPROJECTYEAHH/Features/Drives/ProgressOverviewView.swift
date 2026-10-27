import SwiftUI
import SwiftData

/// Plain counts of what you've recorded. Not a driving score.
struct ProgressOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var drives: [Drive]
    @Query private var checks: [ParkingCheck]

    var body: some View {
        let stats = ProgressStats(trips: drives, checks: checks)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    LotCircleButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                }
                Text("Your progress").font(LotType.display).foregroundStyle(Lot.warmWhite)

                VStack(alignment: .leading, spacing: 20) {
                    row("\(stats.tripCount)", "trips recorded", since: stats.firstTripDate)
                    row("\(stats.parkingCheckCount)", "parking checks saved")
                    row("\(stats.reflectionCount)", "drives with your own notes")
                }

                if !stats.practiced.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Situations you've practiced").font(LotType.headline).foregroundStyle(Lot.warmWhite)
                        FlowLayout {
                            ForEach(stats.practiced) { item in
                                LotChip(text: "\(item.skill.title) · \(item.count)", symbol: item.skill.symbol)
                            }
                        }
                    }
                }

                Text("These are counts of what you've logged, not a measure of how well you drive. More trips doesn't mean better driving, so there's no score here.")
                    .font(LotType.caption).foregroundStyle(Lot.muted)
            }
            .padding(Lot.Space.gutter)
            .padding(.top, 48)
        }
        .scrollIndicators(.hidden)
        .clearsTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .lotScreen()
    }

    private func row(_ value: String, _ label: String, since: Date? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value).font(LotType.numeral(44)).foregroundStyle(Lot.warmWhite)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(LotType.body).foregroundStyle(Lot.warmWhite)
                if let since { Text("since \(since.formatted(.dateTime.month(.abbreviated).day()))").font(LotType.labelSmall).foregroundStyle(Lot.muted) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
