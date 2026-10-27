import SwiftUI

enum CarBodyStyle: String, CaseIterable, Identifiable {
    case sedan, hatchback, suv, pickup, coupe, van

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedan: "Sedan"
        case .hatchback: "Hatchback"
        case .suv: "SUV"
        case .pickup: "Pickup"
        case .coupe: "Coupe"
        case .van: "Van"
        }
    }
}

enum CarWheelStyle: String, CaseIterable, Identifiable {
    case sport, classic, offroad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sport: "Sport"
        case .classic: "Classic"
        case .offroad: "Off-road"
        }
    }
}

/// Everything needed to draw a stylized 3D car.
struct CarSpec: Equatable {
    var body: CarBodyStyle
    var wheels: CarWheelStyle
    var colorHex: String
    /// Imported .usdz scan. When set, it replaces the stylized model.
    var modelData: Data?
    /// A model from the library. Used when no imported scan is set.
    var libraryModelID: String?
    /// Bumps when a downloaded model becomes available, so the view redraws.
    var libraryVersion = 0

    init(car: Car) {
        body = car.bodyStyle
        wheels = car.wheelStyle
        colorHex = car.colorHex
        modelData = car.modelData
        libraryModelID = car.libraryModelID
        libraryVersion = CarModelLibrary.shared.cacheVersion
    }

    init(body: CarBodyStyle, wheels: CarWheelStyle, colorHex: String, modelData: Data? = nil, libraryModelID: String? = nil) {
        self.body = body
        self.wheels = wheels
        self.colorHex = colorHex
        self.modelData = modelData
        self.libraryModelID = libraryModelID
        libraryVersion = CarModelLibrary.shared.cacheVersion
    }

    /// Changes whenever something that affects the drawing changes.
    var signature: String {
        "\(body.rawValue)|\(wheels.rawValue)|\(colorHex)|\(modelData?.count ?? 0)|\(libraryModelID ?? "-")|\(libraryVersion)"
    }
}
