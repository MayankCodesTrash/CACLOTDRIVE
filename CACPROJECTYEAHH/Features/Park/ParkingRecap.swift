import SwiftUI

/// Shareable image for a parking check. Built only from what the user saved.
struct ParkingRecapCard: View {
    let check: ParkingCheck
    let photo: UIImage?

    var body: some View {
        ZStack {
            background
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: Color.black.opacity(0.88), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 3) {
                        Text("LOT").font(.system(size: 15, weight: .black)).foregroundStyle(Lot.warmWhite)
                        Circle().fill(Lot.lime).frame(width: 5, height: 5)
                    }
                    Spacer()
                    Text(check.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Lot.warmWhite.opacity(0.85))
                }
                Spacer()
                Text("Parking check").font(.system(size: 13, weight: .semibold)).foregroundStyle(Lot.lime)
                Text(headline)
                    .font(.system(size: 34, weight: .heavy)).foregroundStyle(Lot.warmWhite)
                    .lineLimit(2).minimumScaleFactor(0.8).padding(.top, 2)
                if !check.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(check.tags.prefix(3)) { tag in
                            Text(tag.title)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Lot.charcoal)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Lot.warmWhite))
                        }
                    }
                    .padding(.top, 10)
                }
                if !check.note.isEmpty {
                    Text(check.note).font(.system(size: 14)).foregroundStyle(Lot.warmWhite.opacity(0.85))
                        .lineLimit(2).padding(.top, 10)
                }
                if check.isDemo && SampleLabels.isVisible {
                    Text("Sample data").font(.system(size: 10, weight: .medium)).foregroundStyle(Lot.warmWhite.opacity(0.6)).padding(.top, 10)
                }
            }
            .padding(24)
        }
        .frame(width: RecapMetrics.size.width, height: RecapMetrics.size.height)
        .clipped()
    }

    private var headline: String {
        check.tries == 1 ? "\(check.maneuver.title) in one try" : "\(check.maneuver.title) parking"
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: RecapMetrics.size.width, height: RecapMetrics.size.height).clipped()
        } else {
            Lot.charcoalRaised
        }
    }
}

struct ParkingRecapSheet: View {
    let check: ParkingCheck

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    private var photo: UIImage? { check.photo.flatMap(UIImage.init(data:)) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - Lot.Space.gutter * 2
            let scale = min(1, width / RecapMetrics.size.width)
            VStack(spacing: 0) {
                HStack {
                    Button("Close") { dismiss() }
                        .font(LotType.caption.weight(.medium)).foregroundStyle(Lot.muted).frame(minHeight: 44)
                    Spacer()
                    Text("Parking recap").font(LotType.title).foregroundStyle(Lot.warmWhite)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, Lot.Space.gutter)

                ScrollView {
                    VStack(spacing: 16) {
                        ParkingRecapCard(check: check, photo: photo)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: RecapMetrics.size.width * scale, height: RecapMetrics.size.height * scale, alignment: .topLeading)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        Text("Check for license plates and people before you share.")
                            .font(LotType.labelSmall).foregroundStyle(Lot.muted)
                    }
                    .padding(.horizontal, Lot.Space.gutter)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                RecapShareBar(image: rendered, title: "Parking recap")
            }
        }
        .lotScreen()
        .task {
            let renderer = ImageRenderer(content: ParkingRecapCard(check: check, photo: photo))
            renderer.scale = 3
            renderer.isOpaque = true
            rendered = renderer.uiImage
        }
    }
}
