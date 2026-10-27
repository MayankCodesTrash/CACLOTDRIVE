import SwiftUI

enum CarPalette {
    static let swatches: [(name: String, hex: String)] = [
        ("White", "F2F2EF"), ("Black", "1D1F22"), ("Silver", "C5CACF"), ("Gray", "6F767C"),
        ("Red", "C0302B"), ("Blue", "2F5FA8"), ("Green", "2F6B4F"), ("Orange", "E98A2B"),
        ("Yellow", "E3C23A"), ("Brown", "6B4A36"),
    ]

    static func name(forHex hex: String) -> String {
        func rgb(_ h: String) -> (Double, Double, Double) {
            let v = UInt32(h.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
            return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
        }
        let t = rgb(hex)
        func d(_ a: (Double, Double, Double)) -> Double { (a.0 - t.0) * (a.0 - t.0) + (a.1 - t.1) * (a.1 - t.1) + (a.2 - t.2) * (a.2 - t.2) }
        return swatches.min { d(rgb($0.hex)) < d(rgb($1.hex)) }?.name ?? "White"
    }
}
