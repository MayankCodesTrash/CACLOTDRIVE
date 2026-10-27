import Foundation
import UIKit

/// Real-world photos from a web image search, using Brave's Image Search API.
/// Docs: https://api-dashboard.search.brave.com/app/documentation/image-search/get-started
/// Google's own Custom Search JSON API is closed to new customers and ends on 2027-01-01, so it isn't used.
/// Results are ordinary web images with unknown licenses, so LOT keeps them in the owner's own Garage and doesn't re-share them.
struct BraveImageSearchService: VehicleImageProviding {
    var apiKey: String?
    var session: URLSession = .shared
    var endpoint = URL(string: "https://api.search.brave.com/res/v1/images/search")!

    private static let blockedWords = ["interior", "engine", "dashboard", "cockpit", "steering", "seat", "trunk", "logo", "emblem", "badge",
                                       "wheel", "rim", "tire", "headlight", "taillight", "diagram", "drawing", "sketch", "cartoon", "crash",
                                       "wreck", "damaged", "toy", "diecast", "model car", "brochure", "poster", "manual", "parts"]
    /// Stock-photo sites stamp watermarks across their previews, and social sites rarely serve the original.
    private static let blockedSources = ["shutterstock", "gettyimages", "istockphoto", "alamy", "depositphotos", "dreamstime", "123rf",
                                         "adobe", "pinterest", "facebook", "instagram", "tiktok", "twitter", "x.com"]

    // MARK: Search

    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        guard let apiKey, !apiKey.isEmpty else { throw VehicleImageError.missingKey }
        guard query.isSearchable else { throw VehicleImageError.noMatch }

        let terms = [String(query.year), query.make, query.model, query.trim, query.colorName, "exterior side view"]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "q", value: terms),
            .init(name: "count", value: "40"),
            .init(name: "safesearch", value: "strict"),
            .init(name: "spellcheck", value: "false"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut {
            throw VehicleImageError.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403, 422: throw VehicleImageError.invalidKey
        case 429: throw VehicleImageError.rateLimited
        default: throw VehicleImageError.badResponse
        }
        let ranked = Self.rank(try Self.parse(data, query: query), for: query)
        guard !ranked.isEmpty else { throw VehicleImageError.noMatch }
        return Array(ranked.prefix(16))
    }

    // MARK: Parsing and ranking (pure, so they can be tested)

    private struct Reply: Decodable {
        struct Result: Decodable {
            struct Thumbnail: Decodable { let src: String? }
            struct Properties: Decodable { let url: String?; let width: Int?; let height: Int? }
            let title: String?
            let url: String?
            let source: String?
            let thumbnail: Thumbnail?
            let properties: Properties?
        }
        let results: [Result]?
    }

    static func parse(_ data: Data, query: VehicleQuery) throws -> [VehicleImageCandidate] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw VehicleImageError.badResponse }
        let makeKey = CarBodyHints.normalize(query.make), modelKey = CarBodyHints.normalize(query.model)
        var seen = Set<String>()
        var out: [VehicleImageCandidate] = []

        for result in reply.results ?? [] {
            guard let imageString = result.properties?.url, let imageURL = URL(string: imageString), imageURL.scheme == "https" else { continue }
            let title = (result.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let source = (result.source ?? imageURL.host ?? "").lowercased()
            let haystack = CarBodyHints.normalize(title + " " + imageString + " " + (result.url ?? ""))
            // The page title or image address has to mention this make and model.
            guard haystack.contains(makeKey), haystack.contains(modelKey) else { continue }
            let lower = (title + " " + imageString).lowercased()
            if blockedWords.contains(where: { lower.contains($0) }) { continue }
            if blockedSources.contains(where: { source.contains($0) }) { continue }
            // Too small to look good in the Garage. Dimensions are sometimes missing, so only reject when known.
            if let w = result.properties?.width, let h = result.properties?.height {
                if w < 700 || h < 350 { continue }
                let aspect = Double(w) / Double(max(h, 1))
                if aspect < 1.1 || aspect > 3.0 { continue }
            }
            guard seen.insert(imageString).inserted else { continue }

            out.append(VehicleImageCandidate(
                id: "web-\(Self.stableHash(imageString))",
                title: title.isEmpty ? "\(query.displayName)" : title,
                imageURL: imageURL,
                pageURL: result.url.flatMap(URL.init(string:)),
                width: result.properties?.width ?? 0,
                height: result.properties?.height ?? 0,
                license: "Web image, © its owner",
                artist: source,
                provider: VehicleImageCandidate.webProvider,
                previewURL: result.thumbnail?.src.flatMap(URL.init(string:))
            ))
        }
        return out
    }

    /// Same address, same id on every launch (Swift's own hashValue changes between runs).
    static func stableHash(_ text: String) -> String {
        String(text.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }, radix: 16)
    }

    /// Best first: matching year and trim, PNGs (often already cut out), side or front views, bigger pictures.
    static func rank(_ candidates: [VehicleImageCandidate], for query: VehicleQuery) -> [VehicleImageCandidate] {
        func score(_ c: VehicleImageCandidate) -> Int {
            let lower = (c.title + " " + c.imageURL.absoluteString).lowercased()
            var total = 0
            if lower.contains(String(query.year)) { total += 12 }
            for word in query.trim.lowercased().split(separator: " ") where lower.contains(word) { total += 6 }
            if !query.colorName.isEmpty, lower.contains(query.colorName.lowercased()) { total += 5 }
            if c.imageURL.pathExtension.lowercased() == "png" || lower.contains("transparent") { total += 10 }
            for angle in ["side", "profile", "front", "three-quarter", "angle", "exterior"] where lower.contains(angle) { total += 3 }
            if c.width >= 1200 { total += 4 } else if c.width >= 900 { total += 2 }
            return total
        }
        return candidates.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element), score(b.element))
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Download

    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage {
        // Original images live on other people's sites and some block hotlinking, so a failure here just means "try the next one".
        try await ImageDownloader.fetch(URLRequest(url: candidate.imageURL, timeoutInterval: 25), session: session)
    }
}

/// Tries web search first (when it's set up and turned on), then Wikimedia Commons. One failing never blocks the other.
struct CompositeVehicleImageService: VehicleImageProviding {
    var web: () -> VehicleImageProviding? = {
        let settings = WebImageSettings.shared
        return settings.isActive ? BraveImageSearchService(apiKey: settings.apiKey) : nil
    }
    var commons: VehicleImageProviding = CommonsVehicleImageService()

    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        var merged: [VehicleImageCandidate] = []
        var firstError: Error?
        if let web = web() {
            do { merged += try await web.search(query) } catch { firstError = error }
        }
        do { merged += try await commons.search(query) } catch { if firstError == nil { firstError = error } }
        if merged.isEmpty { throw firstError ?? VehicleImageError.noMatch }
        return merged
    }

    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage {
        if candidate.isWebImage { return try await BraveImageSearchService(apiKey: nil).download(candidate) }
        return try await commons.download(candidate)
    }
}
