import SwiftUI

/// Generative road-scene artwork. Stands in for photos on demo posts and
/// for user drives that have no photo, so the feed is immersive from day one.
enum SceneStyle: String, CaseIterable, Identifiable {
    case dusk, coast, forest, mesa, overcast, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dusk: "Dusk"
        case .coast: "Coast"
        case .forest: "Forest"
        case .mesa: "Mesa"
        case .overcast: "Overcast"
        case .night: "Night"
        }
    }

    /// Picks artwork that matches when the drive happened.
    static func forTime(_ date: Date) -> SceneStyle {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .coast
        case 11..<17: .mesa
        case 17..<20: .dusk
        default: .night
        }
    }

    fileprivate var sky: [Color] {
        switch self {
        case .dusk: [Color(hex: 0x2A1B3D), Color(hex: 0xC4566B), Color(hex: 0xF2A65A)]
        case .coast: [Color(hex: 0x16405A), Color(hex: 0x3C8DA8), Color(hex: 0xF0D9B5)]
        case .forest: [Color(hex: 0x1B3A2E), Color(hex: 0x5E8B5A), Color(hex: 0xE4E6B0)]
        case .mesa: [Color(hex: 0x4A2A22), Color(hex: 0xD0703F), Color(hex: 0xF7C98B)]
        case .overcast: [Color(hex: 0x1C2226), Color(hex: 0x4A5860), Color(hex: 0x9DAAB0)]
        case .night: [Color(hex: 0x070B0A), Color(hex: 0x10231D), Color(hex: 0x2C5A3F)]
        }
    }

    fileprivate var sun: Color {
        switch self {
        case .dusk: Color(hex: 0xFFD58A)
        case .coast: Color(hex: 0xFFF1CE)
        case .forest: Color(hex: 0xF8F3C0)
        case .mesa: Color(hex: 0xFFE6B0)
        case .overcast: Color(hex: 0xDDE5E7)
        case .night: Color(hex: 0xDDEBD2)
        }
    }

    fileprivate var farHills: Color {
        switch self {
        case .dusk: Color(hex: 0x3B2A4F)
        case .coast: Color(hex: 0x1F5A6B)
        case .forest: Color(hex: 0x2B5A3F)
        case .mesa: Color(hex: 0x7A3B2A)
        case .overcast: Color(hex: 0x2D373C)
        case .night: Color(hex: 0x14281F)
        }
    }

    fileprivate var nearHills: Color {
        switch self {
        case .dusk: Color(hex: 0x22192F)
        case .coast: Color(hex: 0x143F4C)
        case .forest: Color(hex: 0x18372A)
        case .mesa: Color(hex: 0x502519)
        case .overcast: Color(hex: 0x1E262A)
        case .night: Color(hex: 0x0C1A14)
        }
    }

    fileprivate var ground: Color {
        switch self {
        case .dusk: Color(hex: 0x171320)
        case .coast: Color(hex: 0x0F2C36)
        case .forest: Color(hex: 0x102419)
        case .mesa: Color(hex: 0x2F1610)
        case .overcast: Color(hex: 0x151B1E)
        case .night: Color(hex: 0x09110E)
        }
    }

    fileprivate var road: Color {
        switch self {
        case .dusk: Color(hex: 0x0E0D14)
        case .coast: Color(hex: 0x0B1B21)
        case .forest: Color(hex: 0x0A130E)
        case .mesa: Color(hex: 0x170B08)
        case .overcast: Color(hex: 0x0C1012)
        case .night: Color(hex: 0x050A08)
        }
    }
}

struct SceneArt: View {
    let style: SceneStyle
    var seed: Int = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let horizon = h * 0.60
            let phase = Double(seed % 17) * 0.7
            let sunX = 0.3 + 0.4 * (Double((seed * 7) % 10) / 10)

            ctx.fill(
                Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)),
                with: .linearGradient(
                    Gradient(colors: style.sky),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: horizon)
                )
            )

            let r = w * 0.17
            let sunRect = CGRect(x: w * sunX - r, y: horizon - r * 1.25, width: r * 2, height: r * 2)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: r * 0.9))
                layer.fill(Path(ellipseIn: sunRect.insetBy(dx: -r * 0.5, dy: -r * 0.5)), with: .color(style.sun.opacity(0.4)))
            }
            ctx.fill(Path(ellipseIn: sunRect), with: .color(style.sun.opacity(0.95)))

            func hills(amplitude: CGFloat, frequency: Double, phase: Double, color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: horizon + 2))
                var x: CGFloat = 0
                while x <= w {
                    let t = Double(x / w)
                    let wave = 0.55 * sin(t * frequency * 2 * .pi + phase) + 0.45 * sin(t * frequency * 2.7 * 2 * .pi + phase * 1.7)
                    path.addLine(to: CGPoint(x: x, y: horizon - amplitude * CGFloat(0.5 + 0.5 * wave)))
                    x += 4
                }
                path.addLine(to: CGPoint(x: w, y: horizon + 2))
                path.closeSubpath()
                ctx.fill(path, with: .color(color))
            }
            hills(amplitude: h * 0.13, frequency: 1.3, phase: phase, color: style.farHills)
            hills(amplitude: h * 0.07, frequency: 2.1, phase: phase + 2, color: style.nearHills)

            ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .color(style.ground))

            let bend = 0.06 * sin(Double(seed))
            let vx = w * (0.5 + bend)
            var road = Path()
            road.move(to: CGPoint(x: vx - w * 0.012, y: horizon))
            road.addLine(to: CGPoint(x: vx + w * 0.012, y: horizon))
            road.addLine(to: CGPoint(x: w * 1.12, y: h))
            road.addLine(to: CGPoint(x: -w * 0.12, y: h))
            road.closeSubpath()
            ctx.fill(road, with: .color(style.road))

            let dashes = 9
            for i in 0..<dashes {
                let t0 = pow(Double(i) / Double(dashes), 2.2)
                let t1 = pow((Double(i) + 0.5) / Double(dashes), 2.2)
                func point(_ t: Double, _ half: Double) -> (CGPoint, CGPoint) {
                    let cx = vx + (w * 0.5 - vx) * t
                    let y = horizon + (h - horizon) * t
                    let hw = w * (0.002 + 0.016 * t) * half
                    return (CGPoint(x: cx - hw, y: y), CGPoint(x: cx + hw, y: y))
                }
                let a = point(t0, 1), b = point(t1, 1)
                var dash = Path()
                dash.move(to: a.0); dash.addLine(to: a.1); dash.addLine(to: b.1); dash.addLine(to: b.0)
                dash.closeSubpath()
                ctx.fill(dash, with: .color(Lot.lime.opacity(0.9)))
            }
        }
        .accessibilityHidden(true)
    }
}
