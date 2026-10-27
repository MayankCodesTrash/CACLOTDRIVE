import SwiftUI

/// Shows the AI's qualitative review. Always labeled as AI, with its limits stated.
struct AIFeedbackCard: View {
    let analysis: ParkingAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Lot.lime)
                Text("AI feedback").font(LotType.title).foregroundStyle(Lot.warmWhite)
                Spacer()
                if analysis.model == SampleParking.modelName && SampleLabels.isVisible { LotChip(text: "Sample feedback") }
            }

            Text(analysis.summary).font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.92))

            if !analysis.assessable {
                Label(analysis.limitations ?? "This photo doesn't show enough to judge the parking.", systemImage: "eye.slash")
                    .font(LotType.caption).foregroundStyle(Lot.muted)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(analysis.findings) { finding in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: symbol(finding.status))
                                .foregroundStyle(finding.status == .good ? Lot.lime : Lot.warmWhite.opacity(0.75))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.aspect.title).font(LotType.caption.weight(.semibold)).foregroundStyle(Lot.warmWhite)
                                Text(finding.observation).font(LotType.caption).foregroundStyle(Lot.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if !analysis.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LotKicker(text: "Try next time")
                        ForEach(analysis.tips, id: \.self) { tip in
                            Text("• \(tip)").font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.9))
                        }
                    }
                }
            }

            Text("Confidence: \(analysis.confidence.rawValue.capitalized). This is not a score.")
                .font(LotType.labelSmall).foregroundStyle(Lot.muted)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Lot.charcoalRaised))
    }

    private func symbol(_ status: ParkingAnalysis.Status) -> String {
        switch status {
        case .good: "checkmark.circle.fill"
        case .okay: "circle.lefthalf.filled"
        case .needsWork: "arrow.triangle.2.circlepath"
        case .unclear: "questionmark.circle"
        }
    }
}
