// Archived with the 3D garage.
// MARK: - 3D model library

@MainActor
@Suite(.serialized)
struct CarModelLibraryTests {
    private func makeEntry(id: String, make: String? = nil, model: String? = nil, body: String = "sedan",
                           from: Int? = nil, to: Int? = nil, file: String = "x.usdz", sha: String? = nil) -> CarModelEntry {
        CarModelEntry(id: id, name: id, bodyStyle: body, make: make, model: model, yearFrom: from, yearTo: to,
                      file: file, texture: nil, paintRegions: nil, sizeBytes: nil, sha256: sha,
                      license: "CC0 1.0", author: "Test", sourceURL: nil, attributionRequired: false)
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func bundledStarterLibraryLoadsAndItsFilesExist() {
        let library = CarModelLibrary()
        #expect(library.entries.count >= 6)
        for entry in library.entries {
            #expect(library.localURL(for: entry) != nil, "missing file for \(entry.id)")
            #expect(!entry.license.isEmpty && !entry.author.isEmpty)
        }
        #expect(library.entries.allSatisfy { !$0.attributionRequired || !$0.author.isEmpty })
    }

    @Test func bodyHintsRecognizeCommonCars() {
        #expect(CarBodyHints.guess(make: "Honda", model: "Civic") == .sedan)
        #expect(CarBodyHints.guess(make: "Honda", model: "CR-V") == .suv)
        #expect(CarBodyHints.guess(make: "Toyota", model: "Tacoma") == .pickup)
        #expect(CarBodyHints.guess(make: "Ford", model: "F-150 XLT") == .pickup)
        #expect(CarBodyHints.guess(make: "Honda", model: "Odyssey") == .van)
        #expect(CarBodyHints.guess(make: "Ford", model: "Mustang GT") == .coupe)
        #expect(CarBodyHints.guess(make: "Unknown", model: "Zzz") == nil)
    }

    @Test func suggestionsPreferExactMakeModelThenBodyType() {
        let library = CarModelLibrary()
        let exact = makeEntry(id: "civic-2009", make: "Honda", model: "Civic", from: 2006, to: 2011)
        let wrongMake = makeEntry(id: "corolla", make: "Toyota", model: "Corolla")
        let generic = makeEntry(id: "generic-sedan")
        let generalSUV = makeEntry(id: "generic-suv", body: "suv")
        library.setEntriesForTesting([generic, wrongMake, generalSUV, exact])

        let result = library.suggestions(make: "Honda", model: "Civic", year: 2009, body: nil).map(\.id)
        #expect(result.first == "civic-2009")
        #expect(result.contains("generic-sedan"))
        #expect(!result.contains("corolla"))
        #expect(!result.contains("generic-suv"))
    }

    @Test func recoloringChangesOnlyThePaintRegionAndKeepsShading() throws {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor(red: 0.5, green: 0.1, blue: 0.1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 16, y: 0, width: 16, height: 16))
        }
        let recolored = try #require(PaletteRecolor.recolor(base, regions: [[0, 0, 32, 16]], toHex: "2060C0"))

        func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let cg = image.cgImage!
            var data = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return (Int(data[0]), Int(data[1]), Int(data[2]))
        }
        let lightSwatch = pixel(recolored, 4, 4), darkSwatch = pixel(recolored, 20, 4), untouched = pixel(recolored, 50, 50)
        #expect(lightSwatch.b > lightSwatch.r)           // now blue
        #expect(lightSwatch.b > darkSwatch.b)            // the lighter swatch stays lighter
        #expect(abs(untouched.r - 51) <= 2)              // outside the region: unchanged dark gray
    }

    @Test func remoteRepositoryDownloadsVerifiesAndCaches() async throws {
        let payload = Data("fake usdz bytes".utf8)
        let manifest = """
        {"version":1,"name":"Test repo","models":[{"id":"remote-civic","name":"Civic","bodyStyle":"sedan","make":"Honda","model":"Civic",
        "yearFrom":2006,"yearTo":2011,"file":"models/civic.usdz","texture":null,"paintRegions":null,"sizeBytes":15,
        "sha256":"\(CarModelLibrary.sha256Hex(payload))","license":"CC-BY 4.0","author":"Someone","sourceURL":null,"attributionRequired":true}]}
        """
        MockURLProtocol.handlers["example.com"] = { request in
            let url = request.url!
            let body = url.lastPathComponent == "civic.usdz" ? payload : Data(manifest.utf8)
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let library = CarModelLibrary(session: mockSession())
        library.remoteURLString = "https://example.com/cars/lot-library-manifest.json"
        await library.refreshRemote()
        #expect(library.remoteStatus == .loaded(count: 1))

        let entry = try #require(library.entry(id: "remote-civic"))
        #expect(library.localURL(for: entry) == nil)               // not downloaded yet
        #expect(await library.ensureAvailable(entry))
        let cached = try #require(library.localURL(for: entry))
        #expect(try Data(contentsOf: cached) == payload)
        #expect(library.suggestions(make: "Honda", model: "Civic", year: 2009, body: nil).first?.id == "remote-civic")

        library.clearDownloads()
        library.remoteURLString = ""
    }

    @Test func aTamperedDownloadIsRejected() async throws {
        let manifest = """
        {"version":1,"name":"Test","models":[{"id":"bad","name":"Bad","bodyStyle":"sedan","make":null,"model":null,"yearFrom":null,"yearTo":null,
        "file":"bad.usdz","texture":null,"paintRegions":null,"sizeBytes":null,"sha256":"0000","license":"CC0 1.0","author":"x","sourceURL":null,"attributionRequired":false}]}
        """
        MockURLProtocol.handlers["example.com"] = { request in
            let url = request.url!
            let body = url.lastPathComponent == "bad.usdz" ? Data("evil".utf8) : Data(manifest.utf8)
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let library = CarModelLibrary(session: mockSession())
        library.remoteURLString = "https://example.com/r/lot-library-manifest.json"
        await library.refreshRemote()
        let entry = try #require(library.entry(id: "bad"))
        #expect(!(await library.ensureAvailable(entry)))
        #expect(library.localURL(for: entry) == nil)
        library.remoteURLString = ""
    }

    @Test func nonHTTPSRepositoriesAreRefused() async {
        let library = CarModelLibrary(session: mockSession())
        library.remoteURLString = "http://example.com/manifest.json"
        await library.refreshRemote()
        if case .failed = library.remoteStatus {} else { Issue.record("expected a failure for http://") }
        library.remoteURLString = ""
    }
}
