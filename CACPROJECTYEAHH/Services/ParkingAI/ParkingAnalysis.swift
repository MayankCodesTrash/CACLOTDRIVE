import Foundation

/// Gemini's read of a parking photo. Deliberately qualitative: no scores, percentages or measurements.
struct ParkingAnalysis: Codable, Equatable {
    enum Confidence: String, Codable { case low, medium, high }
    enum Aspect: String, Codable {
        case inLines, centering, straightness, spacing, curb

        var title: String {
            switch self {
            case .inLines: "Inside the lines"
            case .centering: "Centered"
            case .straightness: "Straightness"
            case .spacing: "Space around the car"
            case .curb: "Distance to the curb"
            }
        }
    }
    enum Status: String, Codable { case good, okay, needsWork, unclear }

    struct Finding: Codable, Equatable, Identifiable {
        var aspect: Aspect
        var status: Status
        var observation: String
        var id: String { aspect.rawValue }
    }

    /// False when the photo doesn't show enough to judge, for example no lines or the car is cut off.
    var assessable: Bool
    var confidence: Confidence
    var summary: String
    var findings: [Finding]
    var tips: [String]
    var limitations: String?

    // Set locally, not by the model.
    var model: String?
    var analyzedAt: Date?
}

enum ParkingAnalysisError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case modelNotFound(String)
    case rateLimited
    case serviceBusy(Int)
    case blocked
    case network(String)
    case badResponse
    case badImage

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your AI API key in Settings first."
        case .invalidKey: "Google didn't accept that API key. Check it in Settings."
        case .modelNotFound(let name): "Google doesn't know a model called \"\(name)\". Change the model name in Settings."
        case .serviceBusy(let code): "Google's AI service answered \(code), which means the model is overloaded or temporarily down. Your key worked. Wait a minute and try again, or pick a different model in Settings."
        case .rateLimited: "Google says you've hit the usage limit for this key. Try again later."
        case .blocked: "Google declined to review this photo."
        case .network(let message): "Couldn't reach Google: \(message)"
        case .badResponse: "Google's reply wasn't in the format LOT expected. Try again."
        case .badImage: "That photo couldn't be prepared for review."
        }
    }
}
