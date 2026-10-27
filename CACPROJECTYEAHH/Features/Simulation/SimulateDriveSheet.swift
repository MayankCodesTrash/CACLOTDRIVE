import SwiftUI
import MapKit

/// Pick a start and an end, then replay a drive between them through the real detection pipeline.
/// The drive follows real roads (from Apple Maps), and the saved trip is labeled "Simulated sensors".
struct SimulateDriveSheet: View {
    let onStart: (TripDetectionService.SimulatedTrip) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from: SimPlace?
    @State private var to: SimPlace?
    @State private var picking: Field?
    @State private var working = false
    @State private var message: String?

    private enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                Spacer()
                Text("Simulate a drive").font(LotType.title).foregroundStyle(Lot.warmWhite)
                Spacer()
                Color.clear.frame(width: 60, height: 44)
            }
            .padding(.horizontal, Lot.Space.gutter)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Choose where the drive starts and ends. LOT finds a route on real roads and replays it as if your phone had recorded it, including a stop and parking at the end.")
                        .font(LotType.caption).foregroundStyle(Lot.muted)

                    VStack(spacing: 12) {
                        placeRow("From", place: from, symbol: "circle") { picking = .from }
                        placeRow("To", place: to, symbol: "mappin.and.ellipse") { picking = .to }
                        Button {
                            withAnimation { swap(&from, &to) }
                        } label: {
                            Label("Swap", systemImage: "arrow.up.arrow.down").font(LotType.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(Lot.muted).frame(minHeight: 44)
                        .disabled(from == nil && to == nil)
                    }

                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle").font(LotType.caption).foregroundStyle(Lot.warmWhite.opacity(0.85))
                    }

                    Button(action: start) {
                        if working { ProgressView().tint(Lot.charcoal) } else { Label("Start drive", systemImage: "play.fill") }
                    }
                    .buttonStyle(LotButtonStyle(fullWidth: true))
                    .disabled(from == nil || to == nil || working)
                    .opacity(from == nil || to == nil ? 0.5 : 1)

                    Button("Use the built-in sample route instead") {
                        onStart(.init(path: SampleRoutes.route(at: 5), title: "Sample drive", destination: ""))
                        dismiss()
                    }
                    .font(LotType.caption).foregroundStyle(Lot.muted).frame(minHeight: 44)

                    Text("The drive is saved to Drives, marked as simulated sensors. LOT then asks whether you were driving and offers a parking photo, just like a real one.")
                        .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                }
                .padding(Lot.Space.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lotScreen()
        .sheet(item: $picking) { field in
            PlaceSearchSheet(title: field == .from ? "Start" : "Destination") { place in
                if field == .from { from = place } else { to = place }
            }
            .presentationBackground(Lot.charcoal)
        }
    }

    private func placeRow(_ label: String, place: SimPlace?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(Lot.lime).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(LotType.labelSmall).foregroundStyle(Lot.muted)
                    Text(place?.name ?? "Choose a place").font(LotType.body.weight(.medium))
                        .foregroundStyle(place == nil ? Lot.muted : Lot.warmWhite).lineLimit(1)
                    if let sub = place?.subtitle, !sub.isEmpty { Text(sub).font(LotType.labelSmall).foregroundStyle(Lot.muted).lineLimit(1) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lot.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Lot.charcoalRaised))
        }
        .buttonStyle(.plain)
    }

    private func start() {
        guard let from, let to else { return }
        working = true
        message = nil
        Task {
            do {
                let route = try await RouteFinder.driving(from: from.item, to: to.item)
                onStart(.init(path: route.points, title: "Drive to \(to.name)", destination: to.name))
                dismiss()
            } catch {
                message = (error as? RouteError)?.errorDescription ?? "Couldn't get directions. Check your connection and try again."
            }
            working = false
        }
    }
}
