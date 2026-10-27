import SwiftUI

/// LOT brand tokens. Charcoal / warm white / electric lime, nothing else is "brand".
enum Lot {
    static let charcoal = Color(hex: 0x101513)
    static let charcoalRaised = Color(hex: 0x1B231E)
    static let elevated = Color(hex: 0x242C24)
    static let warmWhite = Color(hex: 0xF7F7F0)
    static let lime = Color(hex: 0xC5FA5B)

    static let hairline = warmWhite.opacity(0.10)
    static let muted = Color(hex: 0xA8B0A8)

    enum Space {
        static let gutter: CGFloat = 20
        static let tabBarClearance: CGFloat = 112
    }
}

/// Modern sans for voice, monospaced caps for small metadata labels.
enum LotType {
    static let display = Font.system(.largeTitle, weight: .heavy)
    static let headline = Font.system(.title2, weight: .bold)
    static let title = Font.system(.title3, weight: .semibold)
    static let body = Font.system(.body)
    static let caption = Font.system(.subheadline)
    static let button = Font.system(.callout, weight: .semibold)
    static let label = Font.system(.footnote, weight: .semibold)
    static let labelSmall = Font.system(.caption, weight: .medium)

    /// Large numerals for stats.
    static func numeral(_ size: CGFloat = 40) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(cleaned, radix: 16) ?? 0x888888)
    }
}

extension View {
    /// Full-screen charcoal canvas used by every tab.
    func lotScreen() -> some View {
        background {
            ZStack {
                Lot.charcoal
                RadialGradient(colors: [Color(hex: 0x3F8F4E).opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 460)
            }
            .ignoresSafeArea()
        }
    }
}

extension Color {
    /// "RRGGBB" for storing a chosen paint color.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
