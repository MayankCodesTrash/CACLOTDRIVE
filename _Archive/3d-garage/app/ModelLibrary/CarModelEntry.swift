import Foundation

/// One car in a model repository. A repository is just a JSON manifest plus the files it points to.
struct CarModelEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let bodyStyle: String
    let make: String?
    let model: String?
    let yearFrom: Int?
    let yearTo: Int?
    /// File name in the app bundle, or a path relative to the manifest's URL for remote repositories.
    let file: String
    /// Optional shared color palette texture. When set with `paintRegions`, the body can be repainted.
    let texture: String?
    /// Pixel rectangles [x, y, width, height] of the palette that hold the body paint.
    let paintRegions: [[Int]]?
    let sizeBytes: Int?
    let sha256: String?
    let license: String
    let author: String
    let sourceURL: String?
    let attributionRequired: Bool

    var isGeneric: Bool { make == nil && model == nil }

    var attributionLine: String {
        "\(name) · \(author) · \(license)"
    }
}

struct CarModelManifest: Codable {
    let version: Int
    let name: String
    let models: [CarModelEntry]
}
