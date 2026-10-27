import Foundation

/// Best-guess body type for popular cars, so a new car can start with a sensible model.
enum CarBodyHints {
    private static let table: [String: CarBodyStyle] = {
        var map: [String: CarBodyStyle] = [:]
        let sedans = ["civic", "corolla", "camry", "accord", "sentra", "altima", "elantra", "sonata", "jetta", "passat", "malibu", "fusion",
                      "mazda3", "mazda6", "legacy", "impreza", "optima", "forte", "cruze", "model3", "models", "a4", "3series", "cclass", "lancer", "versa", "rio", "accent"]
        let hatchbacks = ["fit", "golf", "yaris", "prius", "veloster", "mini", "cooper", "soul", "fiesta", "focus", "leaf", "bolt", "gti", "matrix", "versa note"]
        let suvs = ["crv", "rav4", "cx5", "cx30", "rogue", "explorer", "tahoe", "suburban", "highlander", "equinox", "forester", "pilot", "4runner",
                    "bronco", "wrangler", "cherokee", "outback", "tucson", "santafe", "sportage", "escape", "edge", "traverse", "tiguan", "hrv", "modely", "crosstrek"]
        let pickups = ["tacoma", "f150", "f250", "silverado", "ram1500", "ram", "tundra", "ranger", "colorado", "frontier", "sierra", "ridgeline", "gladiator", "maverick"]
        let coupes = ["mustang", "camaro", "challenger", "brz", "86", "gr86", "miata", "mx5", "370z", "350z", "z4", "supra", "corvette", "wrx", "charger", "genesiscoupe", "rx8"]
        let vans = ["odyssey", "sienna", "caravan", "transit", "promaster", "pacifica", "sprinter", "grandcaravan", "transitconnect"]
        for name in sedans { map[name] = .sedan }
        for name in hatchbacks { map[name] = .hatchback }
        for name in suvs { map[name] = .suv }
        for name in pickups { map[name] = .pickup }
        for name in coupes { map[name] = .coupe }
        for name in vans { map[name] = .van }
        return map
    }()

    static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func guess(make: String, model: String) -> CarBodyStyle? {
        let key = normalize(model)
        guard !key.isEmpty else { return nil }
        if let hit = table[key] { return hit }
        // "Civic Si", "F-150 XLT": accept the longest known name the text starts with.
        return table.keys.sorted { $0.count > $1.count }.first { key.hasPrefix($0) }.flatMap { table[$0] }
    }
}
