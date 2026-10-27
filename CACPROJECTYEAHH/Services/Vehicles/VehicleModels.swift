import Foundation

/// What the user typed about their car. Only these words are ever sent to the image provider.
struct VehicleQuery: Equatable {
    var year: Int
    var make: String
    var model: String
    var trim: String
    var colorName: String

    init(year: Int, make: String, model: String, trim: String = "", colorName: String = "") {
        self.year = year
        self.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trim = trim.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorName = colorName
    }

    init(car: Car) {
        self.init(year: car.year, make: car.make, model: car.model, trim: car.trim, colorName: CarPalette.name(forHex: car.colorHex))
    }

    var isSearchable: Bool { !make.isEmpty && !model.isEmpty }

    /// Color is deliberately left out: a different paint color shouldn't throw away a good photo.
    var signature: String { "\(year)|\(make.lowercased())|\(model.lowercased())|\(trim.lowercased())" }

    var displayName: String {
        [String(year), make, model, trim].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// One possible picture of the car, with the license information that has to travel with it.
struct VehicleImageCandidate: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let imageURL: URL
    let pageURL: URL?
    let width: Int
    let height: Int
    let license: String
    let artist: String
    let provider: String
    /// Small picture for the picker grid, when the provider supplies one.
    var previewURL: URL? = nil

    static let webProvider = "Web search"
    static let commonsProvider = "Wikimedia Commons"

    /// Web results are ordinary copyrighted photos. They're fine for the owner's own Garage, but LOT doesn't re-share them.
    var isWebImage: Bool { provider == Self.webProvider }
}

enum VehicleImageMode: String, Codable {
    case automatic, chosen, ownPhoto
}

/// Saved next to the processed image so the Garage can show credit and know when to refresh.
struct VehicleImageMeta: Codable, Equatable {
    var signature: String
    var mode: VehicleImageMode
    var candidate: VehicleImageCandidate?
    var savedAt: Date
    /// False when the background couldn't be removed and the photo is shown as is. Missing in older saves, which were all cutouts.
    var cutout: Bool? = nil

    var isCutout: Bool { cutout ?? true }
}

enum VehicleImageError: LocalizedError, Equatable {
    case offline
    case noMatch
    case badResponse
    case badImage
    case cutoutFailed
    case poorCutout
    case missingKey
    case invalidKey
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .offline: "No internet connection."
        case .noMatch: "No matching photo found."
        case .badResponse: "The image service gave an unexpected reply."
        case .badImage: "That image couldn't be read."
        case .cutoutFailed: "The car couldn't be separated from its background."
        case .poorCutout: "The cutout didn't look reliable, so it wasn't used."
        case .missingKey: "Add a web search key in Settings first."
        case .invalidKey: "The web search service didn't accept that key."
        case .rateLimited: "The web search service says you've used up its limit for now."
        }
    }
}
