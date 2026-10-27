import SwiftUI

/// The dominant element on Today: the latest trip, big image, minimal text.
struct FeaturedTripCard: View {
    let trip: Drive
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: trip) {
                Color.clear
                    .aspectRatio(0.86, contentMode: .fit)
                    .overlay { DriveArtwork(drive: trip) }
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.45),
                            .init(color: Lot.charcoal.opacity(0.92), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) {
                            LotChip(text: "Latest drive")
                            if trip.isDemo { DemoBadge() }
                        }
                        .padding(18)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.title)
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundStyle(Lot.warmWhite)
                                .lineLimit(2)
                            Text(meta).font(LotType.body).foregroundStyle(Lot.warmWhite.opacity(0.85))
                        }
                        .padding(22)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button(action: onShare) {
                    Label("Share Recap", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LotButtonStyle(fullWidth: true))

                NavigationLink(value: trip) { Text("Details") }
                    .buttonStyle(LotButtonStyle(kind: .ghost))
            }
        }
        .padding(.horizontal, Lot.Space.gutter)
    }

    private var meta: String {
        var parts = [TripFormat.dayAndTime(trip.date)]
        if trip.durationSeconds > 0 { parts.append(TripFormat.duration(trip.durationSeconds)) }
        if let car = trip.car?.nickname, !car.isEmpty { parts.append(car) }
        return parts.joined(separator: " · ")
    }
}
