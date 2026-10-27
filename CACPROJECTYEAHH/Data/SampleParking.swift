import UIKit

/// Sample parking photos and sample "AI feedback" for the demo data. The pictures are drawn, not photographed,
/// and the feedback is written by hand to match each picture. Nothing here came from Gemini (model is "sample").
enum SampleParking {
    static let modelName = "sample"

    /// How well parked each sample attempt was, oldest first. 0 is crooked and off-center, 1 is neat.
    static let quality: [Double] = [0.1, 0.25, 0.3, 0.5, 0.55, 0.8, 0.85, 0.95]

    /// A top-down picture of a space with a car in it. Worse parking means a bigger tilt and sideways shift.
    static func image(quality q: Double, seed: Int) -> Data? {
        let size = CGSize(width: 600, height: 750)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let tilt = (1 - q) * 0.30 * (seed.isMultiple(of: 2) ? 1 : -1)
        let shift = (1 - q) * 80 * (seed.isMultiple(of: 2) ? -1 : 1)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            var generator = SeededGenerator(seed: UInt64(seed + 7))
            for _ in 0..<500 {
                UIColor(white: .random(in: 0.22...0.34, using: &generator), alpha: 0.5).setFill()
                c.fill(CGRect(x: .random(in: 0...600, using: &generator), y: .random(in: 0...750, using: &generator), width: 3, height: 3))
            }
            UIColor(white: 0.93, alpha: 1).setFill()
            c.fill(CGRect(x: 140, y: 60, width: 10, height: 630))
            c.fill(CGRect(x: 450, y: 60, width: 10, height: 630))
            c.fill(CGRect(x: 140, y: 60, width: 320, height: 10))

            c.saveGState()
            c.translateBy(x: 300 + shift, y: 400)
            c.rotate(by: tilt)
            let body = CGRect(x: -95, y: -200, width: 190, height: 400)
            UIColor(red: 0.91, green: 0.54, blue: 0.17, alpha: 1).setFill()
            UIBezierPath(roundedRect: body, cornerRadius: 46).fill()
            UIColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: -74, y: -110, width: 148, height: 70), cornerRadius: 22).fill()
            UIBezierPath(roundedRect: CGRect(x: -74, y: 70, width: 148, height: 64), cornerRadius: 22).fill()
            UIColor(white: 0, alpha: 0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: -80, y: -34, width: 160, height: 100), cornerRadius: 30).fill()
            c.restoreGState()
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    /// Hand-written feedback that matches `quality`. Statuses only, never a score.
    static func analysis(quality q: Double, date: Date) -> ParkingAnalysis {
        func status(_ threshold: (needs: Double, okay: Double)) -> ParkingAnalysis.Status {
            q < threshold.needs ? .needsWork : (q < threshold.okay ? .okay : .good)
        }
        let inLines = status((0.3, 0.6)), centering = status((0.4, 0.75)), straight = status((0.35, 0.7))
        let observations: [ParkingAnalysis.Aspect: [ParkingAnalysis.Status: String]] = [
            .inLines: [.needsWork: "The car crosses the line on one side.", .okay: "The car is inside the lines, but close to one of them.", .good: "Both sides sit clearly inside the painted lines."],
            .centering: [.needsWork: "The car is pushed well toward one line.", .okay: "A little closer to one line than the other.", .good: "There is about the same gap on both sides."],
            .straightness: [.needsWork: "The car is angled across the space.", .okay: "A slight angle, noticeable from above.", .good: "The car lines up with the painted lines."],
        ]
        let pairs: [(ParkingAnalysis.Aspect, ParkingAnalysis.Status)] = [(.inLines, inLines), (.centering, centering), (.straightness, straight)]
        let findings: [ParkingAnalysis.Finding] = pairs.map {
            .init(aspect: $0.0, status: $0.1, observation: observations[$0.0]?[$0.1] ?? "")
        }
        let summary: String, tips: [String]
        switch q {
        case ..<0.4:
            summary = "The car is angled and sits over one line. There is room to improve the entry."
            tips = ["Start the turn a little later so you can drive in straighter.", "Aim at the middle of the space, not the nearest line."]
        case ..<0.7:
            summary = "Mostly inside the lines, with a slight angle. The entry is getting steadier."
            tips = ["Pause when the front wheels cross the line and check both sides.", "Straighten the wheel before you stop."]
        default:
            summary = "The car sits inside the lines, centered and straight."
            tips = ["Nice and tidy. Keep checking both mirrors as you pull in."]
        }
        return ParkingAnalysis(assessable: true, confidence: .medium, summary: summary, findings: findings, tips: tips,
                               limitations: nil, model: modelName, analyzedAt: date)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 29)
    }
}
