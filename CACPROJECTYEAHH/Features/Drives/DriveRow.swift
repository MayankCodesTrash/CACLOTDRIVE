import SwiftUI

/// Trip summary used in the Drives timeline.
struct DriveRow: View {
    let drive: Drive
    var thumbnail: CGFloat = 84

    var body: some View {
        HStack(spacing: 16) {
            Color.clear
                .frame(width: thumbnail, height: thumbnail)
                .overlay { DriveArtwork(drive: drive) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(drive.title).font(LotType.title).lineLimit(1).foregroundStyle(Lot.warmWhite)
                Text(meta).font(LotType.caption).foregroundStyle(Lot.muted).lineLimit(1)
                HStack(spacing: 6) {
                    if drive.needsReview { LotChip(text: "Needs review", filled: true) }
                    if drive.isPassenger { LotChip(text: "Passenger", symbol: "person.2") }
                    if let car = drive.car?.nickname, !car.isEmpty { LotChip(text: car, symbol: "car.side") }
                    if drive.isDemo { DemoBadge() }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts = [drive.date.formatted(.dateTime.hour().minute())]
        if drive.durationSeconds > 0 { parts.append(TripFormat.duration(drive.durationSeconds)) }
        if let meters = drive.distanceMeters { parts.append(TripFormat.distance(meters)) }
        return parts.joined(separator: " · ")
    }
}
