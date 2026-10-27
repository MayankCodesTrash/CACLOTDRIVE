import UIKit

/// Bundled transparent vehicle illustrations, so the Garage looks right offline.
/// They are rendered from the CC0 Kenney Car Kit, and are labeled as illustrations in the UI because they are not the user's car.
enum DemoVehicleLibrary {
    static let colors: [(name: String, hex: String)] = [
        ("white", "F2F2EF"), ("black", "1D1F22"), ("silver", "C5CACF"),
        ("red", "C0302B"), ("blue", "2F5FA8"), ("orange", "E98A2B"),
    ]

    static func image(body: CarBodyStyle, colorHex: String) -> UIImage? {
        let name = "demo-\(body.rawValue)-\(nearestColorName(to: colorHex))"
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static func image(for car: Car) -> UIImage? {
        let body = CarBodyHints.guess(make: car.make, model: car.model) ?? car.bodyStyle
        return image(body: body, colorHex: car.colorHex)
    }

    static func nearestColorName(to hex: String) -> String {
        let target = rgb(hex)
        return colors.min { distance(rgb($0.hex), target) < distance(rgb($1.hex), target) }?.name ?? "white"
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        return (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }

    private static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        (a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)
    }
}
