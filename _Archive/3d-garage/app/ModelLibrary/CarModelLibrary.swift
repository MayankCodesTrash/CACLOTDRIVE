import Foundation
import UIKit
import CryptoKit
import Observation

/// The car model library: models that ship with the app, plus an optional online repository.
/// A repository is a static JSON manifest and files, so adding a car means adding files, not shipping an app update.
@Observable
final class CarModelLibrary {
    static let shared = CarModelLibrary()
    static let bundledManifestName = "lot-library-manifest"
    private static let remoteKey = "lot.models.remoteManifest"
    private static let maxDownloadBytes = 60_000_000

    enum RemoteStatus: Equatable {
        case none
        case loading
        case loaded(count: Int)
        case failed(String)
    }

    private(set) var entries: [CarModelEntry] = []
    private(set) var remoteStatus: RemoteStatus = .none
    private(set) var downloading: Set<String> = []
    /// Bumped whenever a download finishes, so views that draw models refresh.
    private(set) var cacheVersion = 0

    @ObservationIgnored private var bundledIDs: Set<String> = []
    @ObservationIgnored private var remoteBase: URL?
    @ObservationIgnored private var recolorCache: [String: UIImage] = [:]
    @ObservationIgnored private let session: URLSession

    var remoteURLString: String {
        get { UserDefaults.standard.string(forKey: Self.remoteKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.remoteKey) }
    }

    init(session: URLSession = .shared) {
        self.session = session
        loadBundled()
    }

    // MARK: Loading

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: Self.bundledManifestName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CarModelManifest.self, from: data) else { return }
        entries = manifest.models
        bundledIDs = Set(manifest.models.map(\.id))
    }

    /// Fetches the online manifest, if a repository URL is set, and merges it in. Online entries win on id clashes.
    func refreshRemote() async {
        let text = remoteURLString
        guard !text.isEmpty else { remoteStatus = .none; return }
        guard let url = URL(string: text), url.scheme == "https" else {
            remoteStatus = .failed("Use an https:// link to a manifest .json file.")
            return
        }
        remoteStatus = .loading
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let manifest = try JSONDecoder().decode(CarModelManifest.self, from: data)
            remoteBase = url.deletingLastPathComponent()
            var merged = entries.filter { bundledIDs.contains($0.id) }
            let remoteIDs = Set(manifest.models.map(\.id))
            merged.removeAll { remoteIDs.contains($0.id) }
            merged.append(contentsOf: manifest.models)
            entries = merged
            remoteStatus = .loaded(count: manifest.models.count)
            cacheVersion += 1
        } catch {
            remoteStatus = .failed("Couldn't read that repository. Check the link and the manifest format.")
        }
    }

    // MARK: Lookup

    /// Test hook: replace the entry list without touching the bundle.
    func setEntriesForTesting(_ list: [CarModelEntry]) {
        entries = list
        bundledIDs = []
    }

    func entry(id: String) -> CarModelEntry? { entries.first { $0.id == id } }

    func isBundled(_ entry: CarModelEntry) -> Bool { bundledIDs.contains(entry.id) }

    /// Best matches first: exact make and model, then the same body type.
    func suggestions(make: String, model: String, year: Int, body: CarBodyStyle?) -> [CarModelEntry] {
        let makeKey = CarBodyHints.normalize(make), modelKey = CarBodyHints.normalize(model)
        let guessedBody = body ?? CarBodyHints.guess(make: make, model: model)

        func score(_ entry: CarModelEntry) -> Int {
            var total = 0
            if let entryMake = entry.make.map(CarBodyHints.normalize), !entryMake.isEmpty, !makeKey.isEmpty {
                if entryMake == makeKey { total += 40 } else { return 0 }
            }
            if let entryModel = entry.model.map(CarBodyHints.normalize), !entryModel.isEmpty, !modelKey.isEmpty {
                if modelKey.hasPrefix(entryModel) || entryModel.hasPrefix(modelKey) { total += 50 } else { return 0 }
                if let from = entry.yearFrom, let to = entry.yearTo, (from...to).contains(year) { total += 10 }
            }
            if let guessedBody, entry.bodyStyle == guessedBody.rawValue { total += 15 }
            return total
        }
        return entries.map { ($0, score($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    // MARK: Files

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CarModels", isDirectory: true)
    }

    private func cachedURL(for file: String) -> URL {
        cacheDirectory.appendingPathComponent(file.replacingOccurrences(of: "/", with: "_"))
    }

    /// A readable file for this entry right now, or nil if it still has to be downloaded.
    func localURL(for entry: CarModelEntry) -> URL? {
        if let url = Bundle.main.url(forResource: (entry.file as NSString).deletingPathExtension, withExtension: (entry.file as NSString).pathExtension) {
            return url
        }
        let cached = cachedURL(for: entry.file)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    private func textureURL(for entry: CarModelEntry) -> URL? {
        guard let texture = entry.texture else { return nil }
        if let url = Bundle.main.url(forResource: (texture as NSString).deletingPathExtension, withExtension: (texture as NSString).pathExtension) {
            return url
        }
        let cached = cachedURL(for: texture)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    /// The body repainted in the car's color, or nil for models that can't be repainted.
    func recoloredPalette(for entry: CarModelEntry, colorHex: String) -> UIImage? {
        guard let regions = entry.paintRegions, !regions.isEmpty,
              let url = textureURL(for: entry), let base = UIImage(contentsOfFile: url.path) else { return nil }
        let key = "\(entry.id)|\(colorHex)"
        if let cached = recolorCache[key] { return cached }
        guard let tinted = PaletteRecolor.recolor(base, regions: regions, toHex: colorHex) else { return nil }
        recolorCache[key] = tinted
        return tinted
    }

    // MARK: Downloading

    /// Downloads a repository model if it isn't on the phone yet. Bundled models return immediately.
    @discardableResult
    func ensureAvailable(_ entry: CarModelEntry) async -> Bool {
        if localURL(for: entry) != nil, entry.texture == nil || textureURL(for: entry) != nil { return true }
        guard let base = remoteBase, !downloading.contains(entry.id) else { return false }
        downloading.insert(entry.id)
        defer { downloading.remove(entry.id) }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try await download(entry.file, base: base, expectedSize: entry.sizeBytes, sha256: entry.sha256)
            if let texture = entry.texture, textureURL(for: entry) == nil {
                try await download(texture, base: base, expectedSize: nil, sha256: nil)
            }
            cacheVersion += 1
            return true
        } catch {
            return false
        }
    }

    private func download(_ path: String, base: URL, expectedSize: Int?, sha256: String?) async throws {
        let source = URL(string: path, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(path)
        guard source.scheme == "https" else { throw URLError(.unsupportedURL) }
        if let expectedSize, expectedSize > Self.maxDownloadBytes { throw URLError(.dataLengthExceedsMaximum) }
        let (data, response) = try await session.data(from: source)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.maxDownloadBytes else {
            throw URLError(.badServerResponse)
        }
        if let sha256, Self.sha256Hex(data) != sha256.lowercased() { throw URLError(.cannotDecodeContentData) }
        try data.write(to: cachedURL(for: path), options: .atomic)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func clearDownloads() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        cacheVersion += 1
    }
}
