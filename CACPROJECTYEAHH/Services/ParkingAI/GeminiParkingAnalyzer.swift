import Foundation
import UIKit

protocol ParkingAnalyzing {
    func analyze(jpeg: Data) async throws -> ParkingAnalysis
}

/// Sends a (redacted) parking photo to Google's Gemini API and decodes a structured, qualitative review.
struct GeminiParkingAnalyzer: ParkingAnalyzing {
    var apiKey: String?
    var model: String
    var session: URLSession = .shared

    static let systemPrompt = """
    You are a supportive driving coach looking at a photo that a teenage learner driver took of their parked car.
    Describe only what is visible. Judge the parking, never the person.
    Rules:
    - If the whole car or the painted parking lines are not clearly visible, set assessable to false and say what is missing in limitations. Do not guess.
    - Never give numeric scores, percentages, distances, angles or measurements. Use only the qualitative statuses.
    - Use status "unclear" for anything you cannot see well. Lower your confidence when the photo is angled, dark, or partly blocked.
    - Do not mention license plates, faces or people.
    - Keep the tone encouraging and practical. Give at most 3 short tips a learner could try next time.
    - The summary is at most 2 sentences.
    """

    static var responseSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "assessable": ["type": "BOOLEAN"],
                "confidence": ["type": "STRING", "enum": ["low", "medium", "high"]],
                "summary": ["type": "STRING"],
                "findings": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "aspect": ["type": "STRING", "enum": ["inLines", "centering", "straightness", "spacing", "curb"]],
                            "status": ["type": "STRING", "enum": ["good", "okay", "needsWork", "unclear"]],
                            "observation": ["type": "STRING"],
                        ],
                        "required": ["aspect", "status", "observation"],
                    ],
                ],
                "tips": ["type": "ARRAY", "items": ["type": "STRING"]],
                "limitations": ["type": "STRING"],
            ],
            "required": ["assessable", "confidence", "summary", "findings", "tips"],
        ]
    }

    func makeRequest(jpeg: Data) throws -> URLRequest {
        guard let apiKey, !apiKey.isEmpty else { throw ParkingAnalysisError.missingKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ParkingAnalysisError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": Self.systemPrompt]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": "Review the parking in this photo and respond using the schema."],
                    ["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ],
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": Self.responseSchema,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func analyze(jpeg: Data) async throws -> ParkingAnalysis {
        let request = try makeRequest(jpeg: jpeg)
        var lastError: Error = ParkingAnalysisError.badResponse
        // 500/503/504 mean Google's side is busy, which usually clears within seconds, so retry a couple of times.
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 2)) }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw ParkingAnalysisError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw ParkingAnalysisError.badResponse }
            switch http.statusCode {
            case 200: return try Self.decode(data, model: model)
            case 400, 401, 403: throw ParkingAnalysisError.invalidKey
            case 404: throw ParkingAnalysisError.modelNotFound(model)
            case 429: throw ParkingAnalysisError.rateLimited
            case 500, 503, 504: lastError = ParkingAnalysisError.serviceBusy(http.statusCode)
            default: throw ParkingAnalysisError.network("status \(http.statusCode)")
            }
        }
        throw lastError
    }

    /// Asks Google for this model's details. Succeeds only if the key is accepted and the model name exists.
    /// No photo is sent, so it is a cheap way to check Settings before a real parking check.
    func testConnection() async throws {
        guard let apiKey, !apiKey.isEmpty else { throw ParkingAnalysisError.missingKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model)") else {
            throw ParkingAnalysisError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw ParkingAnalysisError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ParkingAnalysisError.badResponse }
        switch http.statusCode {
        case 200: return
        case 400, 401, 403: throw ParkingAnalysisError.invalidKey
        case 404: throw ParkingAnalysisError.modelNotFound(model)
        case 429: throw ParkingAnalysisError.rateLimited
        case 500, 503, 504: throw ParkingAnalysisError.serviceBusy(http.statusCode)
        default: throw ParkingAnalysisError.network("status \(http.statusCode)")
        }
    }

    static func decode(_ data: Data, model: String, now: Date = .now) throws -> ParkingAnalysis {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParkingAnalysisError.badResponse
        }
        if let feedback = root["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw ParkingAnalysisError.blocked
        }
        guard let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first,
              let json = text.data(using: .utf8),
              var analysis = try? JSONDecoder().decode(ParkingAnalysis.self, from: json) else {
            throw ParkingAnalysisError.badResponse
        }
        analysis.model = model
        analysis.analyzedAt = now
        analysis.tips = Array(analysis.tips.prefix(3))
        return analysis
    }
}
