import SwiftUI

/// Logical size of every recap card. Exported at 3x, so 1080 x 1350.
enum RecapMetrics {
    static let size = CGSize(width: 360, height: 450)
}

struct RecapCard: View {
    let style: RecapStyle
    let content: RecapContent

    var body: some View {
        Group {
            switch style {
            case .night: NightRecap(content: content)
            case .photoDump: PhotoDumpRecap(content: content)
            case .minimal: MinimalRecap(content: content)
            }
        }
        .frame(width: RecapMetrics.size.width, height: RecapMetrics.size.height)
        .clipped()
    }
}

private struct Wordmark: View {
    var color: Color = Lot.warmWhite

    var body: some View {
        HStack(spacing: 3) {
            Text("LOT").font(.system(size: 15, weight: .black)).foregroundStyle(color)
            Circle().fill(Lot.lime).frame(width: 5, height: 5)
        }
    }
}

private struct SampleMark: View {
    var color: Color
    var body: some View {
        Text("Sample data").font(.system(size: 10, weight: .medium)).foregroundStyle(color.opacity(0.6))
    }
}

// MARK: Night Drive

private struct NightRecap: View {
    let content: RecapContent

    var body: some View {
        ZStack {
            background
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.45), location: 0),
                .init(color: Color.black.opacity(0.15), location: 0.35),
                .init(color: Color.black.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Wordmark()
                    Spacer()
                    Text(content.dateText).font(.system(size: 13, weight: .medium)).foregroundStyle(Lot.warmWhite.opacity(0.8))
                }
                Spacer()
                if !content.route.isEmpty {
                    RouteLine(points: content.route, color: Lot.lime, lineWidth: 3)
                        .frame(height: 120)
                        .shadow(color: Lot.lime.opacity(0.55), radius: 8)
                        .padding(.bottom, 18)
                }
                Text(content.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Lot.warmWhite)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !content.caption.isEmpty {
                    Text(content.caption).font(.system(size: 15)).foregroundStyle(Lot.warmWhite.opacity(0.85))
                        .lineLimit(3).padding(.top, 6)
                }
                HStack(spacing: 14) {
                    ForEach(content.stats, id: \.self) { stat in
                        Text(stat).font(.system(size: 14, weight: .semibold)).foregroundStyle(Lot.lime)
                    }
                    Spacer()
                    if content.isSample { SampleMark(color: Lot.warmWhite) }
                }
                .padding(.top, 14)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var background: some View {
        if let photo = content.photos.first {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: RecapMetrics.size.width, height: RecapMetrics.size.height).clipped()
        } else {
            SceneArt(style: content.route.isEmpty ? content.scene : .night, seed: content.sceneSeed)
        }
    }
}

// MARK: Photo Dump

private struct PhotoDumpRecap: View {
    let content: RecapContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            Lot.warmWhite
            polaroids
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(content.title)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Lot.charcoal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(content.caption.isEmpty ? content.dateText : content.caption)
                    .font(.system(size: 15))
                    .foregroundStyle(Lot.charcoal.opacity(0.7))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ForEach(content.stats, id: \.self) { stat in
                        Text(stat)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Lot.charcoal)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Lot.charcoal.opacity(0.08)))
                    }
                    Spacer()
                    if content.isSample { SampleMark(color: Lot.charcoal) }
                }
                .padding(.top, 6)
            }
            .padding(24)

            Text("LOT")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Lot.charcoal)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Lot.lime))
                .rotationEffect(.degrees(-6))
                .position(x: 304, y: 38)
        }
    }

    private var polaroids: some View {
        let items: [Polaroid.Source] = content.photos.isEmpty
            ? [.scene(content.scene, content.sceneSeed)]
            : content.photos.map { .photo($0) }
        let layouts: [(CGFloat, CGFloat, Double)] = items.count == 1
            ? [(180, 150, -3)]
            : items.count == 2 ? [(120, 140, -6), (240, 170, 5)] : [(105, 135, -7), (250, 150, 6), (175, 195, -2)]
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, source in
                let l = layouts[index]
                Polaroid(source: source, width: items.count == 1 ? 184 : 150)
                    .rotationEffect(.degrees(l.2))
                    .position(x: l.0, y: l.1 + 8)
            }
        }
        .frame(width: RecapMetrics.size.width, height: 300)
    }
}

private struct Polaroid: View {
    enum Source { case photo(UIImage), scene(SceneStyle, Int) }
    let source: Source
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch source {
                case .photo(let image): Image(uiImage: image).resizable().scaledToFill()
                case .scene(let style, let seed): SceneArt(style: style, seed: seed)
                }
            }
            .frame(width: width - 16, height: (width - 16) * 1.15)
            .clipped()
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: width, height: (width - 16) * 1.15 + 40)
        .background(Color.white)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }
}

// MARK: Minimal

private struct MinimalRecap: View {
    let content: RecapContent

    var body: some View {
        ZStack {
            Lot.warmWhite
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Wordmark(color: Lot.charcoal)
                    Spacer()
                    Text(content.dateText).font(.system(size: 13, weight: .medium)).foregroundStyle(Lot.charcoal.opacity(0.6))
                }
                Spacer()
                if content.route.isEmpty {
                    Text(content.durationText ?? content.dateText)
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .foregroundStyle(Lot.charcoal)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    RouteLine(points: content.route, color: Lot.charcoal, lineWidth: 3, markerColor: Lot.lime)
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                }
                Spacer()
                Text(content.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Lot.charcoal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !content.caption.isEmpty {
                    Text(content.caption).font(.system(size: 14)).foregroundStyle(Lot.charcoal.opacity(0.65))
                        .lineLimit(2).padding(.top, 4)
                }
                Rectangle().fill(Lot.charcoal.opacity(0.12)).frame(height: 1).padding(.vertical, 14)
                HStack {
                    Text(content.stats.joined(separator: "  ·  "))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Lot.charcoal)
                    Spacer()
                    if content.isSample { SampleMark(color: Lot.charcoal) }
                }
            }
            .padding(24)
        }
    }
}
