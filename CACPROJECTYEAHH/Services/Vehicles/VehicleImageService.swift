import Foundation
import UIKit

protocol VehicleImageProviding {
    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate]
    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage
}

/// Finds car photos on Wikimedia Commons. It needs no API key, so no secret ships in the app.
/// Docs: https://www.mediawiki.org/wiki/API:Imageinfo and https://www.mediawiki.org/wiki/API:Search
/// Photos there are mostly regular pictures with backgrounds, so they go through background removal afterwards.
struct CommonsVehicleImageService: VehicleImageProviding {
    var session: URLSession = .shared
    var endpoint = URL(string: "https://commons.wikimedia.org/w/api.php")!

    /// Wikimedia asks every client to identify itself. Put a real contact (email or site) here before a public release.
    static let userAgent = "LOT-Garage/1.0 (Congressional App Challenge student prototype; contact: add-a-contact-before-release) URLSession"

    private static let blockedWords = ["interior", "engine", "dashboard", "cockpit", "steering", "seat", "trunk", "logo", "emblem", "badge",
                                       "wheel", "headlight", "taillight", "diagram", "drawing", "sketch", "crash", "wreck", "damaged",
                                       "burnt", "fire", "museum", "model car", "toy", "scale model", "brochure", "advert", "poster", "cutaway"]
    private static let allowedMime: Set<String> = ["image/jpeg", "image/png"]

    // MARK: Search

    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        guard query.isSearchable else { throw VehicleImageError.noMatch }
        var seen = Set<String>()
        var merged: [VehicleImageCandidate] = []

        // First the precise search, then a looser one without the year, so rare years still find something.
        let searches = [
            [String(query.year), query.make, query.model, query.trim].filter { !$0.isEmpty }.joined(separator: " "),
            [query.make, query.model].joined(separator: " "),
        ]
        for text in searches {
            let found = try await request(text: text, query: query)
            for candidate in found where seen.insert(candidate.id).inserted { merged.append(candidate) }
            if merged.count >= 8 { break }
        }
        let ranked = Self.rank(merged, for: query)
        guard !ranked.isEmpty else { throw VehicleImageError.noMatch }
        return Array(ranked.prefix(12))
    }

    private func request(text: String, query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "search"),
            .init(name: "gsrsearch", value: "\(text) filetype:bitmap"),
            .init(name: "gsrnamespace", value: "6"),
            .init(name: "gsrlimit", value: "20"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|size|mime|extmetadata"),
            .init(name: "iiurlwidth", value: "1280"),
            .init(name: "iiextmetadatafilter", value: "LicenseShortName|Artist|Credit|AttributionRequired"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut {
            throw VehicleImageError.offline
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VehicleImageError.badResponse }
        return try Self.parse(data, query: query)
    }

    // MARK: Parsing and ranking (pure, so they can be tested)

    private struct Reply: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let pageid: Int
            let title: String
            let index: Int?
            let imageinfo: [Info]?
        }
        struct Info: Decodable {
            let thumburl: String?
            let url: String?
            let descriptionurl: String?
            let width: Int?
            let height: Int?
            let mime: String?
            let extmetadata: [String: Meta]?
        }
        struct Meta: Decodable { let value: String? }
        let query: Query?
    }

    static func parse(_ data: Data, query: VehicleQuery) throws -> [VehicleImageCandidate] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw VehicleImageError.badResponse }
        let makeKey = CarBodyHints.normalize(query.make), modelKey = CarBodyHints.normalize(query.model)
        var out: [(Int, VehicleImageCandidate)] = []
        for page in reply.query?.pages ?? [] {
            guard let info = page.imageinfo?.first, let mime = info.mime, allowedMime.contains(mime),
                  let width = info.width, let height = info.height, width >= 900,
                  let urlString = info.thumburl ?? info.url, let url = URL(string: urlString),
                  let license = info.extmetadata?["LicenseShortName"]?.value, !license.isEmpty else { continue }

            let title = page.title.replacingOccurrences(of: "File:", with: "")
            let lower = title.lowercased()
            let key = CarBodyHints.normalize(title)
            // The file name has to mention this make and model, which keeps unrelated photos out.
            guard key.contains(makeKey), key.contains(modelKey) else { continue }
            if blockedWords.contains(where: { lower.contains($0) }) { continue }

            let artist = stripHTML(info.extmetadata?["Artist"]?.value ?? info.extmetadata?["Credit"]?.value ?? "Unknown author")
            out.append((page.index ?? Int.max, VehicleImageCandidate(
                id: "commons-\(page.pageid)", title: title, imageURL: url,
                pageURL: info.descriptionurl.flatMap(URL.init(string:)), width: width, height: height,
                license: license, artist: artist, provider: VehicleImageCandidate.commonsProvider)))
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Higher score first. Search order breaks ties because Commons already ranks by relevance.
    static func rank(_ candidates: [VehicleImageCandidate], for query: VehicleQuery) -> [VehicleImageCandidate] {
        func score(_ candidate: VehicleImageCandidate) -> Int {
            let lower = candidate.title.lowercased()
            var total = 0
            // Files usually start with the model year ("2009 Honda Civic ..."). Trust that over a year mentioned elsewhere.
            if let lead = Int(lower.prefix(4)), (1900...2100).contains(lead) {
                let gap = abs(lead - query.year)
                total += gap == 0 ? 30 : gap <= 1 ? 22 : gap <= 4 ? 6 : -25
            } else if lower.contains(String(query.year)) {
                total += 8
            }
            for word in query.trim.lowercased().split(separator: " ") where lower.contains(word) { total += 8 }
            if !query.colorName.isEmpty, lower.contains(query.colorName.lowercased()) { total += 6 }
            for angle in ["front", "side", "left", "right", "three-quarter", "3-4"] where lower.contains(angle) { total += 3 }
            let aspect = Double(candidate.width) / Double(max(candidate.height, 1))
            if (1.3...2.3).contains(aspect) { total += 5 }
            return total
        }
        return candidates.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element), score(b.element))
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Download

    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage {
        var request = URLRequest(url: candidate.imageURL, timeoutInterval: 30)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await ImageDownloader.fetch(request, session: session)
    }
}

/// Downloads an image with a size cap, so one huge or hostile file can't fill memory.
enum ImageDownloader {
    static let maxBytes = 12_000_000

    static func fetch(_ request: URLRequest, session: URLSession) async throws -> UIImage {
        guard request.url?.scheme == "https" else { throw VehicleImageError.badResponse }
        var request = request
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw VehicleImageError.badResponse }
            if http.expectedContentLength > Int64(maxBytes) { throw VehicleImageError.badResponse }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw VehicleImageError.badResponse }
            }
            guard let image = UIImage(data: data) else { throw VehicleImageError.badImage }
            return image
        } catch let error as VehicleImageError {
            throw error
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw VehicleImageError.offline
        } catch {
            throw VehicleImageError.badResponse
        }
    }
}
