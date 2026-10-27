import Foundation
import UIKit
import Observation

/// Where a car's garage picture currently comes from.
enum VehicleImageState: Equatable {
    case idle
    case working(String)
    /// A cached cutout of a real photo.
    case photo
    /// Showing a bundled illustration. `reason` explains why, if automatic lookup didn't work.
    case demo(reason: String?)
}

/// Coordinates the whole pipeline for each car: cache, search, download, cutout, fallback.
@MainActor
@Observable
final class VehicleImageStore {
    static let shared = VehicleImageStore()
    private static let onlineKey = "lot.garage.findImagesOnline"

    /// Bumps whenever any car's picture changes, so views redraw.
    private(set) var version = 0
    private(set) var states: [UUID: VehicleImageState] = [:]

    @ObservationIgnored var provider: VehicleImageProviding
    @ObservationIgnored var remover: BackgroundRemoving
    @ObservationIgnored var cache: VehicleImageCache
    @ObservationIgnored private var memory: [UUID: UIImage] = [:]
    @ObservationIgnored private var cutoutFlags: [UUID: Bool] = [:]
    @ObservationIgnored private var running: Set<UUID> = []

    init(provider: VehicleImageProviding = CompositeVehicleImageService(),
         remover: BackgroundRemoving = VehicleBackgroundRemovalService(),
         cache: VehicleImageCache = VehicleImageCache()) {
        self.provider = provider
        self.remover = remover
        self.cache = cache
    }

    var findsImagesOnline: Bool {
        get { UserDefaults.standard.object(forKey: Self.onlineKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.onlineKey) }
    }

    // MARK: Reading

    func state(for car: Car) -> VehicleImageState { states[car.id] ?? .idle }

    /// What to draw right now: the cached cutout if there is one, otherwise a bundled illustration.
    func image(for car: Car) -> UIImage? {
        _ = version
        if let cached = memory[car.id] { return cached }
        if let loaded = cache.load(car.id) {
            memory[car.id] = loaded.image
            cutoutFlags[car.id] = loaded.meta.isCutout
            return loaded.image
        }
        return DemoVehicleLibrary.image(for: car)
    }

    /// False when the Garage is showing a photo as is, because its background couldn't be removed.
    func isCutout(_ car: Car) -> Bool {
        _ = image(for: car)
        return cutoutFlags[car.id] ?? true
    }

    func isShowingRealPhoto(_ car: Car) -> Bool { memory[car.id] != nil || cache.meta(car.id) != nil }

    func credit(for car: Car) -> VehicleImageCandidate? { cache.meta(car.id)?.candidate }

    // MARK: Automatic lookup

    /// Makes sure the car has a good picture. Does nothing if a current one is already cached.
    func resolve(_ car: Car, force: Bool = false) async {
        let id = car.id
        let query = VehicleQuery(car: car)
        // Once a car has been looked at this session, don't hit the network again unless asked to.
        if !force, states[id] != nil { return }
        if !force, let meta = cache.meta(id), meta.signature == query.signature || meta.mode == .ownPhoto {
            states[id] = .photo
            return
        }
        guard !running.contains(id) else { return }
        running.insert(id)
        defer { running.remove(id) }

        // An older own-photo from before the Garage redesign.
        if !force, cache.meta(id) == nil, let own = car.photo, let image = UIImage(data: own),
           let cut = try? await remover.cutout(image) {
            store(cut, meta: VehicleImageMeta(signature: query.signature, mode: .ownPhoto, candidate: nil, savedAt: .now), for: id)
            return
        }

        guard query.isSearchable else { useDemo(car, reason: nil); return }
        guard findsImagesOnline else { useDemo(car, reason: "Online car images are turned off in Settings."); return }

        states[id] = .working("Finding your car…")
        do {
            let candidates = try await provider.search(query)
            var lastError: Error = VehicleImageError.noMatch
            var firstPhoto: (UIImage, VehicleImageCandidate)?
            var cutoutFailures = 0
            for candidate in candidates.prefix(6) {
                do {
                    states[id] = .working("Cutting out the background…")
                    let photo = try await provider.download(candidate)
                    do {
                        let cut = try await remover.cutout(photo)
                        store(cut, meta: VehicleImageMeta(signature: query.signature, mode: .automatic, candidate: candidate, savedAt: .now, cutout: true), for: id)
                        return
                    } catch let error as VehicleImageError where error == .cutoutFailed || error == .poorCutout {
                        if firstPhoto == nil { firstPhoto = (photo, candidate) }
                        cutoutFailures += 1
                        lastError = error
                        // If the cutout keeps failing (for example Vision can't run on this device), stop downloading more photos.
                        if cutoutFailures >= 3 { break }
                    }
                } catch {
                    lastError = error
                }
            }
            // No clean cutout, but a real photo was found: show it as is rather than falling back to an illustration.
            if let (photo, candidate) = firstPhoto {
                store(VehicleBackgroundRemovalService.normalize(photo, maxDimension: 1600),
                      meta: VehicleImageMeta(signature: query.signature, mode: .automatic, candidate: candidate, savedAt: .now, cutout: false), for: id)
                return
            }
            throw lastError
        } catch {
            useDemo(car, reason: Self.message(for: error))
        }
    }

    // MARK: Manual choices

    func candidates(for car: Car) async throws -> [VehicleImageCandidate] {
        try await provider.search(VehicleQuery(car: car))
    }

    func choose(_ candidate: VehicleImageCandidate, for car: Car) async throws {
        let id = car.id
        states[id] = .working("Cutting out the background…")
        do {
            let photo = try await provider.download(candidate)
            let (image, isCut) = await cutoutOrOriginal(photo)
            store(image, meta: VehicleImageMeta(signature: VehicleQuery(car: car).signature, mode: .chosen, candidate: candidate, savedAt: .now, cutout: isCut), for: id)
        } catch {
            states[id] = isShowingRealPhoto(car) ? .photo : .demo(reason: Self.message(for: error))
            version += 1
            throw error
        }
    }

    func useOwnPhoto(_ data: Data, for car: Car) async throws {
        guard let photo = UIImage(data: data) else { throw VehicleImageError.badImage }
        let id = car.id
        states[id] = .working("Cutting out the background…")
        let (image, isCut) = await cutoutOrOriginal(photo)
        store(image, meta: VehicleImageMeta(signature: VehicleQuery(car: car).signature, mode: .ownPhoto, candidate: nil, savedAt: .now, cutout: isCut), for: id)
    }

    /// Tries to remove the background. If that isn't possible, the photo is used as is.
    private func cutoutOrOriginal(_ photo: UIImage) async -> (UIImage, Bool) {
        do { return (try await remover.cutout(photo), true) }
        catch { return (VehicleBackgroundRemovalService.normalize(photo, maxDimension: 1600), false) }
    }

    func useIllustration(for car: Car) {
        cache.remove(car.id)
        memory[car.id] = nil
        useDemo(car, reason: nil)
    }

    func forget(_ car: Car) {
        cache.remove(car.id)
        memory[car.id] = nil
        states[car.id] = nil
        version += 1
    }

    // MARK: Internals

    private func store(_ image: UIImage, meta: VehicleImageMeta, for id: UUID) {
        do {
            try cache.save(image, meta: meta, for: id)
            memory[id] = image
            cutoutFlags[id] = meta.isCutout
            states[id] = .photo
        } catch {
            states[id] = .demo(reason: "Couldn't save the image on this phone.")
        }
        version += 1
    }

    private func useDemo(_ car: Car, reason: String?) {
        memory[car.id] = nil
        cutoutFlags[car.id] = nil
        states[car.id] = .demo(reason: reason)
        version += 1
    }

    static func message(for error: Error) -> String {
        switch error as? VehicleImageError {
        case .offline: "You're offline, so LOT is showing an illustration."
        case .noMatch: "No matching photo found, so LOT is showing an illustration."
        case .cutoutFailed, .poorCutout: "Couldn't isolate the car in the photo, so LOT is showing an illustration."
        case .invalidKey: "The web search key wasn't accepted, so LOT is showing an illustration. Check it in Settings."
        case .rateLimited: "The web search limit was reached, so LOT is showing an illustration."
        default: "Couldn't load a photo, so LOT is showing an illustration."
        }
    }
}

#if DEBUG
extension VehicleImageStore {
    /// Debug: installs a cutout made on a Mac (the simulator can't run Vision's foreground model) as this car's picture.
    func debugInstall(cutoutAt path: String, for car: Car) {
        guard let image = UIImage(contentsOfFile: path), let trimmed = VehicleBackgroundRemovalService.trimToOpaqueBounds(image) else { return }
        let candidate = VehicleImageCandidate(
            id: "commons-debug", title: "2009 Honda Civic DX-G Sedan in Tango Red Pearl, front left, 2020-10-13.jpg",
            imageURL: URL(string: "https://commons.wikimedia.org")!, pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:2009_Honda_Civic_DX-G_Sedan_in_Tango_Red_Pearl,_front_left,_2020-10-13.jpg"),
            width: 2589, height: 1648, license: "CC BY-SA 4.0", artist: "Elise240SX", provider: "Wikimedia Commons")
        store(trimmed, meta: VehicleImageMeta(signature: VehicleQuery(car: car).signature, mode: .automatic, candidate: candidate, savedAt: .now), for: car.id)
    }

    /// Debug: runs search, download and cutout for a query and writes what happened to the temp folder.
    static func debugPipeline() async {
        let query = VehicleQuery(year: 2009, make: "Honda", model: "Civic")
        var log = ""
        let provider = CommonsVehicleImageService()
        do {
            let found = try await provider.search(query)
            log += "search ok: \(found.count)\n"
            for (i, c) in found.prefix(4).enumerated() {
                log += "[\(i)] \(c.title) \(c.width)x\(c.height) \(c.license) | \(c.artist)\n"
                do {
                    let photo = try await provider.download(c)
                    log += "   downloaded \(Int(photo.size.width))x\(Int(photo.size.height))\n"
                    let cut = try await VehicleBackgroundRemovalService().cutout(photo)
                    log += "   CUTOUT OK \(Int(cut.size.width))x\(Int(cut.size.height))\n"
                    try? cut.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cutout-\(i).png"))
                } catch { log += "   failed: \(error) | \(VehicleBackgroundRemovalService.lastDebugNote)\n" }
            }
        } catch { log += "search failed: \(error)\n" }
        try? log.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pipeline.log"), atomically: true, encoding: .utf8)
    }
}
#endif
