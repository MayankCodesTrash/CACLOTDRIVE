import Foundation
import UIKit

/// Keeps the finished cutout on disk, one PNG plus a small JSON file per car, so nothing is fetched twice.
struct VehicleImageCache {
    var directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VehicleImages", isDirectory: true)
    }

    private func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }
    private func metaURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    func load(_ id: UUID) -> (image: UIImage, meta: VehicleImageMeta)? {
        guard let data = try? Data(contentsOf: metaURL(id)),
              let meta = try? JSONDecoder().decode(VehicleImageMeta.self, from: data),
              let image = UIImage(contentsOfFile: imageURL(id).path) else { return nil }
        return (image, meta)
    }

    func meta(_ id: UUID) -> VehicleImageMeta? {
        (try? Data(contentsOf: metaURL(id))).flatMap { try? JSONDecoder().decode(VehicleImageMeta.self, from: $0) }
    }

    func save(_ image: UIImage, meta: VehicleImageMeta, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let png = image.pngData() else { throw VehicleImageError.badImage }
        try png.write(to: imageURL(id), options: .atomic)
        try JSONEncoder().encode(meta).write(to: metaURL(id), options: .atomic)
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: imageURL(id))
        try? FileManager.default.removeItem(at: metaURL(id))
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
