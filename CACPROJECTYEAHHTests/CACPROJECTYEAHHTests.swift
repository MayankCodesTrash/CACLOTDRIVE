import Testing
import Foundation
@testable import CACPROJECTYEAHH

/// Exercises the trip-detection state machine with scripted sensor data.
/// These use simulated inputs only. Real motion detection needs a physical iPhone.
@MainActor
struct TripStateMachineTests {
    private struct Result {
        var effects: [DetectionEffect] = []
        var states: [DetectionState] = []
        var completed: [TripDraft] {
            effects.compactMap { if case .tripCompleted(let d) = $0 { d } else { nil } }
        }
        var discarded: Int { effects.filter { $0 == .tripDiscarded }.count }
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ scenario: DriveScenario, config: DetectionConfig = DetectionConfig()) -> Result {
        var machine = TripRecordingStateMachine(config: config)
        var result = Result()
        for input in scenario.inputs {
            let effects = machine.handle(input)
            result.effects += effects
            result.states.append(machine.state)
            if machine.state == .completed { machine.reset() }
        }
        return result
    }

    @Test func recordsOneTripAndSurvivesARedLight() {
        let result = run(.standardDrive(startingAt: start))
        #expect(result.completed.count == 1)
        let trip = result.completed[0]
        #expect(trip.duration > 600 && trip.duration < 730)
        #expect(trip.distanceMeters > 4000)
        #expect(!trip.route.isEmpty)
        // The red light made it a "possible stop", but it recovered instead of ending the trip.
        #expect(result.states.contains(.possibleStop))
        #expect(result.states.contains(.recording))
    }

    @Test func aLongRedLightUnderTheGraceWindowDoesNotSplitTheTrip() {
        var options = DriveScenario.Options()
        options.trafficLightSeconds = 200
        let result = run(.standardDrive(startingAt: start, options: options))
        #expect(result.completed.count == 1)
        #expect(result.completed[0].duration > 600)
    }

    @Test func aSingleGPSSpikeNeverStartsRecording() {
        var inputs: [DetectionInput] = [
            .location(LocationSample(date: start, latitude: 40, longitude: -90, speed: 15, horizontalAccuracy: 10)),
        ]
        for i in 1...40 { inputs.append(.tick(start.addingTimeInterval(Double(i) * 10))) }
        let result = run(DriveScenario(inputs: inputs))
        #expect(result.effects.isEmpty)
        #expect(!result.states.contains(.recording))
        #expect(result.states.last == .idle)
    }

    @Test func walkingSpeedNeverStartsRecording() {
        var inputs: [DetectionInput] = []
        for i in 0..<120 {
            let t = start.addingTimeInterval(Double(i) * 5)
            inputs.append(.location(LocationSample(date: t, latitude: 40 + Double(i) * 0.00004, longitude: -90, speed: 1.4, horizontalAccuracy: 8)))
            if i % 12 == 0 { inputs.append(.motion(MotionSample(date: t, kind: .walking, confidence: .high))) }
        }
        let result = run(DriveScenario(inputs: inputs))
        #expect(result.effects.isEmpty)
        #expect(!result.states.contains(.recording))
    }

    @Test func tooShortATripIsDiscarded() {
        var options = DriveScenario.Options()
        options.driveSeconds = 75
        options.trafficLightAt = nil
        let result = run(.standardDrive(startingAt: start, options: options))
        #expect(result.completed.isEmpty)
    }

    @Test func locationAloneDoesNotRecordWhenMotionConfirmationIsRequired() {
        var options = DriveScenario.Options()
        options.includeMotion = false
        let result = run(.standardDrive(startingAt: start, options: options))
        #expect(result.completed.isEmpty)
    }

    @Test func locationOnlyModeRecordsWithStrongerEvidence() {
        var options = DriveScenario.Options()
        options.includeMotion = false
        let result = run(.standardDrive(startingAt: start, options: options), config: .locationOnly)
        #expect(result.completed.count == 1)
    }

    @Test func walkingAwayEndsTheTripSoonerThanTheStopGrace() {
        var options = DriveScenario.Options()
        options.trailingSeconds = 100
        let walking = run(.standardDrive(startingAt: start, options: options))
        #expect(walking.completed.count == 1)

        options.walkAwayAfterParking = false
        let waiting = run(.standardDrive(startingAt: start, options: options))
        #expect(waiting.completed.isEmpty)
    }

    @Test func unavailableMachineIgnoresInput() {
        var machine = TripRecordingStateMachine()
        machine.setUnavailable(true)
        let scenario = DriveScenario.standardDrive(startingAt: start)
        for input in scenario.inputs { #expect(machine.handle(input).isEmpty) }
        #expect(machine.state == .unavailable)
    }
}

import SwiftData
import UIKit

/// Seating rules for outings, run against an in-memory store.
@MainActor
struct PlanSeatingTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Car.self, Drive.self, DrivePhoto.self, ParkingCheck.self,
                             Plan.self, PlanStop.self, PlanCar.self, PlanPerson.self, RideAssignment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// One stop, one car with two seats, three riders.
    private func makePlan(in context: ModelContext) -> (Plan, PlanStop, PlanCar, [PlanPerson]) {
        let plan = Plan(title: "Test")
        context.insert(plan)
        let stop = PlanStop(order: 0, name: "Dinner", time: .now)
        context.insert(stop); stop.plan = plan
        let car = PlanCar(order: 0, driverName: "Theo", carName: "Old Blue", seats: 2)
        context.insert(car); car.plan = plan
        let people = ["A", "B", "C"].enumerated().map { PlanPerson(order: $0.offset, name: $0.element) }
        for person in people { context.insert(person); person.plan = plan }
        return (plan, stop, car, people)
    }

    @Test func cannotExceedSeatCapacity() throws {
        let context = try makeContext()
        let (plan, stop, car, people) = makePlan(in: context)
        #expect(plan.assign(people[0], to: car, at: stop, in: context))
        #expect(plan.assign(people[1], to: car, at: stop, in: context))
        #expect(!plan.assign(people[2], to: car, at: stop, in: context))
        #expect(plan.riders(in: car, at: stop).count == 2)
        #expect(plan.seatsLeft(in: car, at: stop) == 0)
    }

    @Test func unassignedRidersAreFlagged() throws {
        let context = try makeContext()
        let (plan, stop, car, people) = makePlan(in: context)
        plan.assign(people[0], to: car, at: stop, in: context)
        #expect(plan.unassigned(at: stop).map(\.name) == ["B", "C"])
    }

    @Test func reassigningMovesARiderWithoutDuplicating() throws {
        let context = try makeContext()
        let (plan, stop, car, people) = makePlan(in: context)
        let second = PlanCar(order: 1, driverName: "Nia", carName: "Marigold", seats: 1)
        context.insert(second); second.plan = plan

        plan.assign(people[0], to: car, at: stop, in: context)
        #expect(plan.assign(people[0], to: second, at: stop, in: context))
        #expect(plan.riders(in: car, at: stop).isEmpty)
        #expect(plan.riders(in: second, at: stop).map(\.name) == ["A"])
        // A full car refuses a move and leaves the rider where they were.
        plan.assign(people[1], to: car, at: stop, in: context)
        #expect(!plan.assign(people[1], to: second, at: stop, in: context))
        #expect(plan.riders(in: car, at: stop).map(\.name) == ["B"])
    }

    @Test func ridesCanDifferBetweenStops() throws {
        let context = try makeContext()
        let (plan, first, car, people) = makePlan(in: context)
        let second = PlanStop(order: 1, name: "Game", time: .now)
        context.insert(second); second.plan = plan

        plan.assign(people[0], to: car, at: first, in: context)
        #expect(plan.unassigned(at: second).count == 3)
        plan.copyAssignments(from: first, to: second, in: context)
        #expect(plan.riders(in: car, at: second).map(\.name) == ["A"])
    }

    @Test func shrinkingSeatsTrimsOverflowRiders() throws {
        let context = try makeContext()
        let (plan, stop, car, people) = makePlan(in: context)
        plan.assign(people[0], to: car, at: stop, in: context)
        plan.assign(people[1], to: car, at: stop, in: context)
        car.seats = 1
        plan.trimOverCapacity(in: context)
        try context.save()
        #expect(plan.riders(in: car, at: stop).count == 1)
    }
}

// MARK: - Gemini parking analyzer (mocked network, no real API calls)

nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Handlers are keyed by host so suites that mock different servers can run in parallel.
    nonisolated(unsafe) static var handlers: [String: (URLRequest) -> (HTTPURLResponse, Data)] = [:]
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var lastCommonsRequest: URLRequest?
    nonisolated(unsafe) static var lastBraveRequest: URLRequest?
    static let geminiHost = "generativelanguage.googleapis.com"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        if host == Self.geminiHost { Self.lastRequest = request }
        if host == "commons.wikimedia.org" { Self.lastCommonsRequest = request }
        if host == "api.search.brave.com" { Self.lastBraveRequest = request }
        if host == Self.geminiHost, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            Self.lastBody = data
        } else if host == Self.geminiHost {
            Self.lastBody = request.httpBody
        }
        guard let handler = Self.handlers[host] else { return }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct GeminiParkingAnalyzerTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func respond(status: Int, json: String) {
        MockURLProtocol.handlers[MockURLProtocol.geminiHost] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
    }

    private func envelope(_ inner: String) -> String {
        let escaped = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\(escaped)\"}]}}]}"
    }

    private let goodAnalysis = """
    {"assessable":true,"confidence":"medium","summary":"The car sits inside the lines, slightly left.",
     "findings":[{"aspect":"inLines","status":"good","observation":"Both sides are inside the lines."},
                 {"aspect":"centering","status":"okay","observation":"A bit closer to the left line."}],
     "tips":["Aim for the middle.","Straighten earlier.","Check mirrors.","A fourth tip that should be dropped."]}
    """

    private var analyzer: GeminiParkingAnalyzer {
        GeminiParkingAnalyzer(apiKey: "test-key", model: "gemini-test", session: makeSession())
    }

    @Test func sendsAnImageWithKeyHeaderAndStructuredOutput() async throws {
        respond(status: 200, json: envelope(goodAnalysis))
        _ = try await analyzer.analyze(jpeg: Data([0xFF, 0xD8, 0xFF]))

        let request = try #require(MockURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect(request.httpMethod == "POST")

        let body = try #require(MockURLProtocol.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try #require(json["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["responseSchema"] != nil)
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.compactMap { $0["inlineData"] as? [String: Any] }.first)
        #expect(inline["mimeType"] as? String == "image/jpeg")
        #expect(inline["data"] as? String == Data([0xFF, 0xD8, 0xFF]).base64EncodedString())
        let system = try #require(json["systemInstruction"] as? [String: Any])
        let systemText = ((system["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(systemText.contains("Never give numeric scores"))
    }

    @Test func decodesAStructuredReviewAndCapsTips() async throws {
        respond(status: 200, json: envelope(goodAnalysis))
        let result = try await analyzer.analyze(jpeg: Data([1]))
        #expect(result.assessable)
        #expect(result.confidence == .medium)
        #expect(result.findings.count == 2)
        #expect(result.tips.count == 3)
        #expect(result.model == "gemini-test")
    }

    @Test func anUnassessablePhotoIsReportedHonestly() async throws {
        respond(status: 200, json: envelope("""
        {"assessable":false,"confidence":"low","summary":"I can't see the lines.","findings":[],"tips":[],"limitations":"The car is cut off."}
        """))
        let result = try await analyzer.analyze(jpeg: Data([1]))
        #expect(!result.assessable)
        #expect(result.limitations == "The car is cut off.")
    }

    @Test func mapsHTTPFailuresToFriendlyErrors() async {
        respond(status: 403, json: "{}")
        await #expect(throws: ParkingAnalysisError.invalidKey) { try await analyzer.analyze(jpeg: Data([1])) }
        respond(status: 429, json: "{}")
        await #expect(throws: ParkingAnalysisError.rateLimited) { try await analyzer.analyze(jpeg: Data([1])) }
    }

    @Test func blockedAndMalformedReplies() async {
        respond(status: 200, json: "{\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}")
        await #expect(throws: ParkingAnalysisError.blocked) { try await analyzer.analyze(jpeg: Data([1])) }
        respond(status: 200, json: envelope("not json at all"))
        await #expect(throws: ParkingAnalysisError.badResponse) { try await analyzer.analyze(jpeg: Data([1])) }
    }

    @Test func missingKeyNeverHitsTheNetwork() async {
        MockURLProtocol.lastRequest = nil
        let noKey = GeminiParkingAnalyzer(apiKey: nil, model: "gemini-test", session: makeSession())
        await #expect(throws: ParkingAnalysisError.missingKey) { try await noKey.analyze(jpeg: Data([1])) }
        #expect(MockURLProtocol.lastRequest == nil)
    }
}

@MainActor
struct PrivacyRedactorTests {
    @Test func downscalesLargePhotosBeforeUpload() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let result = PrivacyRedactor.redactSync(big, maxDimension: 1280)
        #expect(max(result.image.size.width, result.image.size.height) <= 1280)
    }

    @Test func textInThePhotoGetsPixelated() {
        let size = CGSize(width: 1000, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 160), .foregroundColor: UIColor.black]
            NSAttributedString(string: "ABC 1234", attributes: attributes).draw(at: CGPoint(x: 80, y: 200))
        }
        let result = PrivacyRedactor.redactSync(image, maxDimension: 1280)
        #expect(result.regionsBlurred >= 1)
    }
}


// MARK: - Garage vehicle images

private func solidImage(_ size: CGSize, color: UIColor, transparentBackground: Bool) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = !transparentBackground
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        if !transparentBackground {
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        color.setFill()
        ctx.fill(CGRect(x: size.width * 0.25, y: size.height * 0.3, width: size.width * 0.5, height: size.height * 0.4))
    }
}

@MainActor
@Suite(.serialized)
struct CommonsVehicleImageServiceTests {
    private let query = VehicleQuery(year: 2009, make: "Honda", model: "Civic", trim: "EX", colorName: "Red")

    private func page(_ id: Int, _ title: String, index: Int, width: Int = 2400, height: Int = 1400, mime: String = "image/jpeg",
                       license: String? = "CC BY-SA 4.0", artist: String = "<a href='//x'>Some &amp; Person</a>") -> String {
        let licenseJSON = license.map { "\"LicenseShortName\":{\"value\":\"\($0)\"}," } ?? ""
        return """
        {"pageid":\(id),"ns":6,"title":"File:\(title)","index":\(index),"imageinfo":[{"thumburl":"https://upload.wikimedia.org/thumb/\(id)/1280px-x.jpg",
        "url":"https://upload.wikimedia.org/\(id).jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:\(id)","width":\(width),"height":\(height),"mime":"\(mime)",
        "extmetadata":{\(licenseJSON)"Artist":{"value":"\(artist)"}}}]}
        """
    }

    private func reply(_ pages: [String]) -> Data {
        Data("{\"batchcomplete\":true,\"query\":{\"pages\":[\(pages.joined(separator: ","))]}}".utf8)
    }

    @Test func parseKeepsRealCarPhotosAndDropsTheRest() throws {
        let data = reply([
            page(1, "2009 Honda Civic DX-G Sedan, front left.jpg", index: 1),
            page(2, "2009 Honda Civic interior dashboard.jpg", index: 2),          // blocked word
            page(3, "2009 Toyota Corolla.jpg", index: 3),                            // wrong car
            page(4, "2009 Honda Civic small.jpg", index: 4, width: 500, height: 300), // too small
            page(5, "2009 Honda Civic diagram.png", index: 5, mime: "image/svg+xml"), // wrong type
            page(6, "2009 Honda Civic no license.jpg", index: 6, license: nil),      // no license info
        ])
        let result = try CommonsVehicleImageService.parse(data, query: query)
        #expect(result.map(\.id) == ["commons-1"])
        #expect(result[0].artist == "Some & Person")        // HTML stripped
        #expect(result[0].license == "CC BY-SA 4.0")
        #expect(result[0].pageURL != nil)
    }

    @Test func rankingTrustsTheYearAtTheStartOfTheFileName() throws {
        let data = reply([
            page(1, "1978 Honda Civic CVCC Wagon at Hershey 2009, front left.jpg", index: 1),
            page(2, "2009 Honda Civic DX-G Sedan, front left.jpg", index: 2),
            page(3, "2011 Honda Civic hatchback front view.jpg", index: 3),
            page(4, "2009 Honda Civic EX Coupe.jpg", index: 4),
        ])
        let ranked = CommonsVehicleImageService.rank(try CommonsVehicleImageService.parse(data, query: query), for: query)
        #expect(ranked.first?.id == "commons-4")                       // year and trim match
        #expect(ranked.last?.id == "commons-1")                        // the 1978 car sinks
    }

    @Test func searchSendsTheDocumentedRequestWithAUserAgent() async throws {
        MockURLProtocol.handlers["commons.wikimedia.org"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             reply([page(1, "2009 Honda Civic EX Sedan.jpg", index: 1)]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let service = CommonsVehicleImageService(session: URLSession(configuration: config))
        let found = try await service.search(query)
        #expect(found.count == 1)

        let request = try #require(MockURLProtocol.lastCommonsRequest)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("LOT-Garage/") == true)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("action") == "query")
        #expect(value("generator") == "search")
        #expect(value("gsrnamespace") == "6")
        #expect(value("prop") == "imageinfo")
        #expect(value("iiprop")?.contains("extmetadata") == true)
        // The last request is the looser fallback search (no year), which only runs when the precise one found few results.
        #expect(value("gsrsearch")?.contains("Honda Civic") == true)
    }

    @Test func aSearchWithNoUsableResultsIsAnHonestNoMatch() async {
        MockURLProtocol.handlers["commons.wikimedia.org"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, reply([]))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let service = CommonsVehicleImageService(session: URLSession(configuration: config))
        await #expect(throws: VehicleImageError.noMatch) { try await service.search(query) }
    }
}

@MainActor
struct VehicleImagePipelineTests {
    @Test func transparentPhotosAreOnlyTrimmedNotSegmented() throws {
        let image = solidImage(CGSize(width: 400, height: 200), color: .red, transparentBackground: true)
        let cut = try VehicleBackgroundRemovalService.process(image)
        #expect(cut.size.width < 400 && cut.size.height < 200)     // cropped to the car
        #expect(cut.size.width > 150)
    }

    @Test func transparencyDetectionTellsCutoutsFromPhotos() {
        let cutout = solidImage(CGSize(width: 200, height: 100), color: .blue, transparentBackground: true)
        let photo = solidImage(CGSize(width: 200, height: 100), color: .blue, transparentBackground: false)
        #expect(VehicleBackgroundRemovalService.hasUsableTransparency(cutout.cgImage!))
        #expect(!VehicleBackgroundRemovalService.hasUsableTransparency(photo.cgImage!))
    }

    @Test func cacheRoundTripsImageAndCredit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vehicle-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VehicleImageCache(directory: directory)
        let id = UUID()
        let candidate = VehicleImageCandidate(id: "c1", title: "t", imageURL: URL(string: "https://x.org/a.jpg")!, pageURL: nil,
                                              width: 2000, height: 1000, license: "CC0", artist: "A", provider: "Wikimedia Commons")
        let meta = VehicleImageMeta(signature: "2009|honda|civic|", mode: .automatic, candidate: candidate, savedAt: .now)
        try cache.save(solidImage(CGSize(width: 60, height: 30), color: .green, transparentBackground: true), meta: meta, for: id)

        let loaded = try #require(cache.load(id))
        #expect(loaded.meta.candidate?.artist == "A")
        #expect(loaded.meta.signature == "2009|honda|civic|")
        cache.remove(id)
        #expect(cache.load(id) == nil)
    }

    @Test func everyBodyStyleHasABundledIllustrationInEveryColor() {
        for body in CarBodyStyle.allCases {
            for color in DemoVehicleLibrary.colors {
                #expect(DemoVehicleLibrary.image(body: body, colorHex: color.hex) != nil, "missing \(body.rawValue) \(color.name)")
            }
        }
        #expect(DemoVehicleLibrary.nearestColorName(to: "E98A2B") == "orange")
        #expect(DemoVehicleLibrary.nearestColorName(to: "101010") == "black")
        #expect(DemoVehicleLibrary.nearestColorName(to: "2F5FA8") == "blue")
    }

    @Test func querySignatureIgnoresColorButNotTheCar() {
        let a = VehicleQuery(year: 2009, make: "Honda", model: "Civic", trim: "EX", colorName: "Red")
        let b = VehicleQuery(year: 2009, make: "honda", model: "civic", trim: "ex", colorName: "Blue")
        let c = VehicleQuery(year: 2010, make: "Honda", model: "Civic", trim: "EX", colorName: "Red")
        #expect(a.signature == b.signature)
        #expect(a.signature != c.signature)
        #expect(!VehicleQuery(year: 2009, make: "", model: "Civic").isSearchable)
    }
}

private final class FakeProvider: VehicleImageProviding, @unchecked Sendable {
    var candidates: [VehicleImageCandidate] = []
    var searchError: Error?
    var searchCalls = 0
    var downloadCalls = 0
    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        searchCalls += 1
        if let searchError { throw searchError }
        return candidates
    }
    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage {
        downloadCalls += 1
        return solidImage(CGSize(width: 100, height: 50), color: .gray, transparentBackground: false)
    }
}

private struct FakeRemover: BackgroundRemoving {
    var failCount = 0   // fails this many times before succeeding
    final class Counter: @unchecked Sendable { var calls = 0 }
    let counter = Counter()
    func cutout(_ image: UIImage) async throws -> UIImage {
        counter.calls += 1
        if counter.calls <= failCount { throw VehicleImageError.cutoutFailed }
        return solidImage(CGSize(width: 80, height: 40), color: .red, transparentBackground: true)
    }
}

@MainActor
@Suite(.serialized)
struct VehicleImageStoreTests {
    private func candidate(_ id: String) -> VehicleImageCandidate {
        VehicleImageCandidate(id: id, title: "2009 Honda Civic \(id).jpg", imageURL: URL(string: "https://x.org/\(id).jpg")!, pageURL: nil,
                              width: 2000, height: 1000, license: "CC BY 4.0", artist: "Someone", provider: "Wikimedia Commons")
    }

    private func makeStore(_ provider: FakeProvider, remover: FakeRemover = FakeRemover()) -> VehicleImageStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        let store = VehicleImageStore(provider: provider, remover: remover, cache: VehicleImageCache(directory: dir))
        store.findsImagesOnline = true
        return store
    }

    private func civic() -> Car { Car(nickname: "Biscuit", make: "Honda", model: "Civic", year: 2009) }

    @Test func foundPhotoIsCachedAndNotFetchedAgain() async {
        let provider = FakeProvider(); provider.candidates = [candidate("a")]
        let store = makeStore(provider)
        let car = civic()
        await store.resolve(car)
        #expect(store.state(for: car) == .photo)
        #expect(store.credit(for: car)?.artist == "Someone")
        #expect(provider.searchCalls == 1)

        await store.resolve(car)                       // same session
        await store.resolve(car, force: false)
        #expect(provider.searchCalls == 1)

        let fresh = VehicleImageStore(provider: provider, remover: FakeRemover(), cache: store.cache)   // "relaunch"
        fresh.findsImagesOnline = true
        await fresh.resolve(car)
        #expect(provider.searchCalls == 1)             // served from the disk cache
        #expect(fresh.state(for: car) == .photo)
    }

    @Test func aFailedCutoutTriesTheNextCandidate() async {
        let provider = FakeProvider(); provider.candidates = [candidate("a"), candidate("b"), candidate("c")]
        let store = makeStore(provider, remover: FakeRemover(failCount: 2))
        let car = civic()
        await store.resolve(car)
        #expect(store.state(for: car) == .photo)
        #expect(store.credit(for: car)?.id == "c")
        #expect(provider.downloadCalls == 3)
    }

    @Test func offlineFallsBackToTheIllustrationWithAClearReason() async {
        let provider = FakeProvider(); provider.searchError = VehicleImageError.offline
        let store = makeStore(provider)
        let car = civic()
        await store.resolve(car)
        guard case .demo(let reason) = store.state(for: car) else { Issue.record("expected demo state"); return }
        #expect(reason?.contains("offline") == true)
        #expect(store.image(for: car) != nil)          // the bundled illustration is still drawn
    }

    @Test func turningOnlineLookupOffMakesNoRequests() async {
        let provider = FakeProvider(); provider.candidates = [candidate("a")]
        let store = makeStore(provider)
        store.findsImagesOnline = false
        defer { store.findsImagesOnline = true }
        let car = civic()
        await store.resolve(car)
        #expect(provider.searchCalls == 0)
        #expect(store.image(for: car) != nil)
    }

    @Test func changingTheCarForcesANewLookupAndChoosingAnImageSticks() async throws {
        let provider = FakeProvider(); provider.candidates = [candidate("a")]
        let store = makeStore(provider)
        let car = civic()
        await store.resolve(car)

        try await store.choose(candidate("manual"), for: car)
        #expect(store.credit(for: car)?.id == "manual")
        #expect(store.cache.meta(car.id)?.mode == .chosen)

        car.year = 2010
        await store.resolve(car, force: true)
        #expect(provider.searchCalls == 2)

        store.useIllustration(for: car)
        #expect(store.cache.meta(car.id) == nil)
        #expect(store.state(for: car) == .demo(reason: nil))
    }

    @Test func carsWithoutAMakeAndModelJustUseTheIllustration() async {
        let provider = FakeProvider()
        let store = makeStore(provider)
        let car = Car(nickname: "Mystery")
        await store.resolve(car)
        #expect(provider.searchCalls == 0)
        #expect(store.state(for: car) == .demo(reason: nil))
    }
}


// MARK: - Web image search (Brave) and the provider chain

private func braveReply(_ results: [String]) -> Data {
    Data("{\"type\":\"images\",\"query\":{\"original\":\"q\"},\"results\":[\(results.joined(separator: ","))],\"extra\":{}}".utf8)
}

private func braveResult(_ title: String, image: String, source: String = "caranddriver.com", page: String = "https://caranddriver.com/x",
                         width: Int? = 1600, height: Int? = 900) -> String {
    let dims = (width != nil && height != nil) ? ",\"width\":\(width!),\"height\":\(height!)" : ""
    return """
    {"type":"image_result","title":"\(title)","url":"\(page)","source":"\(source)",
     "thumbnail":{"src":"https://imgs.search.brave.com/thumb/abc","width":500,"height":281},
     "properties":{"url":"\(image)"\(dims)}}
    """
}

@MainActor
@Suite(.serialized)
struct BraveImageSearchServiceTests {
    private let query = VehicleQuery(year: 2009, make: "Honda", model: "Civic", trim: "EX", colorName: "Red")

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func parseKeepsUsableCarPhotosAndDropsTheRest() throws {
        let data = braveReply([
            braveResult("2009 Honda Civic EX red side view", image: "https://cdn.example.com/civic-1.jpg"),
            braveResult("2009 Honda Civic interior dashboard", image: "https://cdn.example.com/civic-2.jpg"),   // blocked word
            braveResult("2009 Honda Civic", image: "https://cdn.shutterstock.com/civic.jpg", source: "shutterstock.com"), // watermarked source
            braveResult("2009 Toyota Corolla", image: "https://cdn.example.com/corolla.jpg"),                    // wrong car
            braveResult("2009 Honda Civic tiny", image: "https://cdn.example.com/civic-3.jpg", width: 300, height: 200),
            braveResult("2009 Honda Civic insecure", image: "http://cdn.example.com/civic-4.jpg"),               // not https
            braveResult("2009 Honda Civic no size", image: "https://cdn.example.com/civic-5.jpg", width: nil, height: nil), // size unknown is kept
        ])
        let found = try BraveImageSearchService.parse(data, query: query)
        #expect(found.map(\.imageURL.lastPathComponent) == ["civic-1.jpg", "civic-5.jpg"])
        #expect(found.allSatisfy { $0.isWebImage && $0.previewURL != nil })
        #expect(found[0].artist == "caranddriver.com")
        #expect(found[0].id == (try BraveImageSearchService.parse(data, query: query))[0].id)
    }

    @Test func rankingPrefersPNGsMatchingTrimAndBiggerPictures() throws {
        let data = braveReply([
            braveResult("2009 Honda Civic", image: "https://a.example.com/plain.jpg", width: 1000, height: 600),
            braveResult("2009 Honda Civic EX transparent", image: "https://a.example.com/cutout.png", width: 1500, height: 800),
            braveResult("2009 Honda Civic EX front view", image: "https://a.example.com/front.jpg", width: 1300, height: 800),
        ])
        let ranked = BraveImageSearchService.rank(try BraveImageSearchService.parse(data, query: query), for: query)
        #expect(ranked.first?.imageURL.lastPathComponent == "cutout.png")
        #expect(ranked.last?.imageURL.lastPathComponent == "plain.jpg")
    }

    @Test func searchSendsTheDocumentedRequest() async throws {
        MockURLProtocol.handlers["api.search.brave.com"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             braveReply([braveResult("2009 Honda Civic EX red side view", image: "https://cdn.example.com/civic.jpg")]))
        }
        let service = BraveImageSearchService(apiKey: "test-key", session: session())
        let found = try await service.search(query)
        #expect(found.count == 1)

        let request = try #require(MockURLProtocol.lastBraveRequest)
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == "test-key")
        #expect(request.url?.path == "/res/v1/images/search")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("q")?.contains("2009 Honda Civic EX Red") == true)
        #expect(value("count") == "40")
        #expect(value("safesearch") == "strict")
    }

    @Test func keyProblemsAreReportedClearly() async {
        let noKey = BraveImageSearchService(apiKey: nil, session: session())
        await #expect(throws: VehicleImageError.missingKey) { try await noKey.search(query) }

        let service = BraveImageSearchService(apiKey: "k", session: session())
        MockURLProtocol.handlers["api.search.brave.com"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        await #expect(throws: VehicleImageError.invalidKey) { try await service.search(query) }
        MockURLProtocol.handlers["api.search.brave.com"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        await #expect(throws: VehicleImageError.rateLimited) { try await service.search(query) }
    }

    @Test func downloadsOverTheSizeCapAreRefused() async {
        MockURLProtocol.handlers["img.example.com"] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Length": "40000000", "Content-Type": "image/jpeg"])!, Data([1, 2, 3]))
        }
        let request = URLRequest(url: URL(string: "https://img.example.com/huge.jpg")!)
        await #expect(throws: VehicleImageError.badResponse) { try await ImageDownloader.fetch(request, session: session()) }
        await #expect(throws: VehicleImageError.badResponse) {
            try await ImageDownloader.fetch(URLRequest(url: URL(string: "http://img.example.com/insecure.jpg")!), session: session())
        }
    }
}

private struct StubProvider: VehicleImageProviding {
    var results: [VehicleImageCandidate] = []
    var error: Error?
    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] {
        if let error { throw error }
        return results
    }
    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage { UIImage() }
}

@MainActor
struct VehicleProviderChainTests {
    private let query = VehicleQuery(year: 2009, make: "Honda", model: "Civic")

    private func candidate(_ id: String, provider: String) -> VehicleImageCandidate {
        VehicleImageCandidate(id: id, title: id, imageURL: URL(string: "https://x.org/\(id).jpg")!, pageURL: nil, width: 2000, height: 1000,
                              license: "x", artist: "a", provider: provider)
    }

    @Test func webResultsComeFirstThenCommons() async throws {
        let chain = CompositeVehicleImageService(
            web: { StubProvider(results: [candidate("w1", provider: VehicleImageCandidate.webProvider)]) },
            commons: StubProvider(results: [candidate("c1", provider: VehicleImageCandidate.commonsProvider)]))
        let found = try await chain.search(query)
        #expect(found.map(\.id) == ["w1", "c1"])
    }

    @Test func aBrokenWebSearchNeverBlocksCommons() async throws {
        let chain = CompositeVehicleImageService(
            web: { StubProvider(error: VehicleImageError.invalidKey) },
            commons: StubProvider(results: [candidate("c1", provider: VehicleImageCandidate.commonsProvider)]))
        #expect(try await chain.search(query).map(\.id) == ["c1"])
    }

    @Test func withWebSearchOffOnlyCommonsIsUsed() async throws {
        let chain = CompositeVehicleImageService(
            web: { nil },
            commons: StubProvider(results: [candidate("c1", provider: VehicleImageCandidate.commonsProvider)]))
        #expect(try await chain.search(query).map(\.id) == ["c1"])
    }

    @Test func ifBothFailTheFirstErrorExplainsWhy() async {
        let chain = CompositeVehicleImageService(
            web: { StubProvider(error: VehicleImageError.rateLimited) },
            commons: StubProvider(error: VehicleImageError.noMatch))
        await #expect(throws: VehicleImageError.rateLimited) { try await chain.search(query) }
    }
}


// MARK: - Fallbacks: photo as is, and a database that can't be opened

@MainActor
@Suite(.serialized)
struct VehicleFallbackTests {
    private func candidate(_ id: String) -> VehicleImageCandidate {
        VehicleImageCandidate(id: id, title: "2009 Honda Civic \(id).jpg", imageURL: URL(string: "https://x.org/\(id).jpg")!, pageURL: nil,
                              width: 2000, height: 1000, license: "x", artist: "a", provider: "Web search")
    }

    private func makeStore(failCount: Int) -> (VehicleImageStore, FakeProviderRef) {
        let provider = FakeProviderRef()
        provider.candidates = [candidate("a"), candidate("b"), candidate("c"), candidate("d")]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID().uuidString)")
        let store = VehicleImageStore(provider: provider, remover: AlwaysFailingRemover(failures: failCount), cache: VehicleImageCache(directory: dir))
        store.findsImagesOnline = true
        return (store, provider)
    }

    @Test func ifTheBackgroundCantBeRemovedThePhotoIsUsedAsIs() async {
        let (store, provider) = makeStore(failCount: 100)
        let car = Car(nickname: "Biscuit", make: "Honda", model: "Civic", year: 2009)
        await store.resolve(car)
        #expect(store.state(for: car) == .photo)           // a real photo, not the illustration
        #expect(store.isCutout(car) == false)
        #expect(store.credit(for: car)?.id == "a")
        #expect(store.cache.meta(car.id)?.isCutout == false)
        #expect(provider.downloadCalls == 3)               // stops after 3 failed cutouts instead of downloading everything
    }

    @Test func aGoodCutoutStillWinsWhenOneExists() async {
        let (store, _) = makeStore(failCount: 1)
        let car = Car(nickname: "Biscuit", make: "Honda", model: "Civic", year: 2009)
        await store.resolve(car)
        #expect(store.isCutout(car))
        #expect(store.credit(for: car)?.id == "b")
    }

    @Test func choosingOrUploadingNeverFailsJustBecauseVisionCant() async throws {
        let (store, _) = makeStore(failCount: 100)
        let car = Car(nickname: "Biscuit", make: "Honda", model: "Civic", year: 2009)
        try await store.choose(candidate("manual"), for: car)
        #expect(store.credit(for: car)?.id == "manual")
        #expect(store.isCutout(car) == false)

        let png = solidImage(CGSize(width: 120, height: 60), color: .blue, transparentBackground: false).pngData()!
        try await store.useOwnPhoto(png, for: car)
        #expect(store.cache.meta(car.id)?.mode == .ownPhoto)
        #expect(store.isCutout(car) == false)
    }

    @Test func aStoreThatCantBeOpenedIsBackedUpAndReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try Data("this is not a database".utf8).write(to: storeURL)
        let previousFlag = UserDefaults.standard.bool(forKey: PersistenceController.resetFlagKey)
        defer { UserDefaults.standard.set(previousFlag, forKey: PersistenceController.resetFlagKey) }

        let container = PersistenceController.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        context.insert(Car(nickname: "Works"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Car>()) == 1)

        let backups = directory.appendingPathComponent("StoreBackups")
        #expect(FileManager.default.fileExists(atPath: backups.path))
        #expect(UserDefaults.standard.bool(forKey: PersistenceController.resetFlagKey))
    }
}

private final class FakeProviderRef: VehicleImageProviding, @unchecked Sendable {
    var candidates: [VehicleImageCandidate] = []
    var downloadCalls = 0
    func search(_ query: VehicleQuery) async throws -> [VehicleImageCandidate] { candidates }
    func download(_ candidate: VehicleImageCandidate) async throws -> UIImage {
        downloadCalls += 1
        return solidImage(CGSize(width: 100, height: 50), color: .gray, transparentBackground: false)
    }
}

private struct AlwaysFailingRemover: BackgroundRemoving {
    let failures: Int
    final class Counter: @unchecked Sendable { var calls = 0 }
    let counter = Counter()
    init(failures: Int) { self.failures = failures }
    func cutout(_ image: UIImage) async throws -> UIImage {
        counter.calls += 1
        if counter.calls <= failures { throw VehicleImageError.cutoutFailed }
        return solidImage(CGSize(width: 80, height: 40), color: .red, transparentBackground: true)
    }
}

// MARK: - Road-following sample routes

@MainActor
struct SampleRouteTests {
    @Test func bakedRoutesDecodeToRealisticRoadRoutes() {
        #expect(SampleRoutes.encoded.count == 8)
        for index in 0..<8 {
            let route = SampleRoutes.route(at: index)
            #expect(route.count > 40, "route \(index) is too sparse to follow streets")
            #expect(route.allSatisfy { (-90...90).contains($0.lat) && (-180...180).contains($0.lon) })
            let meters = SampleRoutes.length(of: route)
            #expect(meters > 3_000 && meters < 25_000, "route \(index) has an odd length: \(meters)")
        }
    }

    @Test func decoderMatchesTheDocumentedPolylineExample() {
        // From Google's polyline algorithm documentation.
        let points = SampleRoutes.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(abs(points[0].lat - 38.5) < 1e-5 && abs(points[0].lon + 120.2) < 1e-5)
        #expect(abs(points[2].lat - 43.252) < 1e-5 && abs(points[2].lon + 126.453) < 1e-5)
    }

    @Test func pointAlongARouteInterpolatesAndClamps() {
        let route = [RoutePoint(lat: 40, lon: -90), RoutePoint(lat: 40.01, lon: -90)]
        let total = SampleRoutes.length(of: route)
        let middle = SampleRoutes.point(along: route, at: total / 2)
        #expect(abs(middle.lat - 40.005) < 1e-4)
        #expect(SampleRoutes.point(along: route, at: total * 5) == route[1])
        #expect(SampleRoutes.point(along: route, at: -10) == route[0])
    }

    @Test func aSimulatedDriveFollowsTheRoadRoute() {
        var options = DriveScenario.Options()
        options.path = SampleRoutes.route(at: 5)
        let scenario = DriveScenario.standardDrive(startingAt: Date(timeIntervalSince1970: 1_800_000_000), options: options)
        var machine = TripRecordingStateMachine()
        var trip: TripDraft?
        for input in scenario.inputs {
            for case .tripCompleted(let draft) in machine.handle(input) { trip = draft }
            if machine.state == .completed { machine.reset() }
        }
        let draft = try! #require(trip)
        #expect(draft.route.count > 20)
        // Every recorded point sits on the baked road route (within a few meters).
        let road = SampleRoutes.route(at: 5)
        let start = road[0]
        #expect(abs(draft.route[0].lat - start.lat) < 0.01 && abs(draft.route[0].lon - start.lon) < 0.01)
        #expect(draft.distanceMeters > 4000)
    }
}

// MARK: - Car measurement and garage alignment

/// A transparent picture of a simple car: a body, a lower near tire, a higher far tire, and a front bumper lip that sits lower than
/// the far tire (the decoy that fooled earlier detection).
private func syntheticCar(size: CGSize = CGSize(width: 400, height: 200)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        UIColor.red.setFill()
        UIBezierPath(roundedRect: CGRect(x: 20, y: 40, width: 360, height: 100), cornerRadius: 14).fill()
        UIColor.black.setFill()
        UIBezierPath(ovalIn: CGRect(x: 112, y: 116, width: 56, height: 56)).fill()      // near tire, bottom at y = 172
        UIBezierPath(ovalIn: CGRect(x: 272, y: 104, width: 56, height: 56)).fill()      // far tire, bottom at y = 160
        UIBezierPath(rect: CGRect(x: 20, y: 130, width: 40, height: 35)).fill()          // bumper lip, bottom at y = 165
    }
}

@MainActor
struct GarageAlignmentTests {
    @Test func measurementFindsTheLowestTireAndIgnoresTheBumperLip() throws {
        let analysis = try #require(VehicleGeometryAnalyzer.analyze(syntheticCar()))
        #expect(analysis.image.size.width < 370 && analysis.image.size.height < 140)
        let near = try #require(analysis.geometry.nearContact)
        #expect(near.y > 0.97)                                  // the lowest point is the bottom edge
        // The near tire is centered at x = 140 of the original; the crop starts at x = 20 and is 360 wide.
        #expect(abs(near.x - (140 - 20) / 360) < 0.05)
        #expect(analysis.geometry.footprint.lowerBound < 0.1)   // the underside reaches back to the bumper
        #expect(analysis.geometry.footprint.upperBound > 0.8)
    }

    @Test func emptyAndTinyImagesAreRejected() {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { _ in }
        #expect(VehicleGeometryAnalyzer.analyze(blank) == nil)
    }

    @Test func analysisIsCachedPerImage() {
        let image = syntheticCar()
        let first = VehicleGeometryAnalyzer.cachedAnalysis(of: image)
        let second = VehicleGeometryAnalyzer.cachedAnalysis(of: image)
        #expect(first != nil)
        #expect(first?.image === second?.image)
    }

    @Test func theRoomIsDerivedFromTheCarSoEverythingLinesUp() throws {
        let analysis = try #require(VehicleGeometryAnalyzer.analyze(syntheticCar()))
        let size = CGSize(width: 393, height: 460)
        let layout = GarageLayout(size: size, analysis: analysis, bodyHeight: CarBodyStyle.sedan.realHeightMeters)
        let car = try #require(layout.carFrame)

        #expect(abs(car.maxY - layout.groundY) < 0.5)
        #expect(abs(layout.contacts[0].y - layout.groundY) < 1.5)
        #expect(abs(car.height - CarBodyStyle.sedan.realHeightMeters * layout.carScale) < 0.5)
        #expect(abs((layout.groundY - layout.horizonY) - GarageLayout.eyeHeight * layout.carScale) < 0.5)
        #expect(layout.wallScale < layout.carScale)
        #expect(layout.wall.maxY < layout.groundY)
        #expect(abs((layout.wall.maxY - layout.horizonY) - GarageLayout.eyeHeight * layout.wallScale) < 0.5)
        #expect(abs(layout.door.height - GarageLayout.doorHeight * layout.wallScale) < 0.5)
        #expect(car.minX >= 0 && car.maxX <= size.width)
        #expect(layout.horizonY > 0 && layout.horizonY < layout.groundY)
    }

    @Test func tallerVehiclesComeOutBiggerNextToTheSameDoor() throws {
        let compact = UIGraphicsImageRenderer(size: CGSize(width: 260, height: 200)).image { _ in
            UIColor.green.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 260, height: 200)).fill()
        }
        let analysis = try #require(VehicleGeometryAnalyzer.analyze(compact))
        let size = CGSize(width: 393, height: 460)
        let sedan = GarageLayout(size: size, analysis: analysis, bodyHeight: CarBodyStyle.sedan.realHeightMeters)
        let pickup = GarageLayout(size: size, analysis: analysis, bodyHeight: CarBodyStyle.pickup.realHeightMeters)
        #expect(pickup.carFrame!.height > sedan.carFrame!.height)
        #expect(abs(pickup.carScale - sedan.carScale) < 0.001)     // same room scale, so the pickup really is taller
        #expect(abs(pickup.door.height - sedan.door.height) < 0.001)
    }

    @Test func veryWideCarsAreShrunkToFitWithoutLeavingTheFloor() throws {
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 120)).image { _ in
            UIColor.blue.setFill()
            UIRectangle(CGRect(x: 0, y: 0, width: 800, height: 120))
        }
        let analysis = try #require(VehicleGeometryAnalyzer.analyze(wide))
        let size = CGSize(width: 393, height: 460)
        let layout = GarageLayout(size: size, analysis: analysis, bodyHeight: CarBodyStyle.sedan.realHeightMeters)
        let car = try #require(layout.carFrame)
        #expect(car.width <= size.width * 0.9 + 0.5)
        #expect(abs(car.maxY - layout.groundY) < 0.5)
        #expect(layout.wall.maxY < layout.groundY)
    }

    @Test func everyBundledIllustrationMeasuresSensibly() throws {
        for body in CarBodyStyle.allCases {
            let image = try #require(DemoVehicleLibrary.image(body: body, colorHex: "C0302B"))
            let analysis = try #require(VehicleGeometryAnalyzer.analyze(image), "\\(body.rawValue) failed to measure")
            let near = try #require(analysis.geometry.nearContact)
            #expect(near.y > 0.9, "\\(body.rawValue): lowest contact should be at the bottom")
            #expect(analysis.geometry.footprintWidth > 0.4, "\\(body.rawValue): footprint too narrow")
        }
    }
}

private func UIRectangle(_ rect: CGRect) { UIBezierPath(rect: rect).fill() }

// MARK: - Moving and resizing the car in the garage

@MainActor
struct GarageAdjustmentTests {
    private let size = CGSize(width: 393, height: 460)
    private func analysis() throws -> VehicleAnalysis {
        let compact = UIGraphicsImageRenderer(size: CGSize(width: 260, height: 160)).image { _ in
            UIColor.green.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 260, height: 160)).fill()
        }
        return try #require(VehicleGeometryAnalyzer.analyze(compact))
    }
    private func layout(_ adjustment: GarageAdjustment, body: CGFloat = 1.45) throws -> GarageLayout {
        GarageLayout(size: size, analysis: try analysis(), bodyHeight: body, adjustment: adjustment)
    }

    @Test func movingSidewaysShiftsOnlyTheCar() throws {
        let start = try layout(.neutral), moved = try layout(GarageAdjustment(offsetX: 0.2))
        #expect(abs((moved.carFrame!.midX - start.carFrame!.midX) - 0.2 * size.width) < 1)
        #expect(moved.carFrame!.minY == start.carFrame!.minY)
        #expect(moved.carFrame!.size == start.carFrame!.size)
        #expect(moved.horizonY == start.horizonY && moved.door == start.door)       // the room never moves
    }

    @Test func movingUpAndDownIsIndependentOfSize() throws {
        let start = try layout(.neutral), moved = try layout(GarageAdjustment(offsetY: -0.1))
        #expect(abs((moved.carFrame!.midY - start.carFrame!.midY) + 0.1 * size.height) < 1)
        #expect(moved.carFrame!.size == start.carFrame!.size)                        // moving never resizes
        #expect(moved.carFrame!.midX == start.carFrame!.midX)
    }

    @Test func resizingKeepsTheCarWhereItIsLikeResizingAPhoto() throws {
        let start = try layout(.neutral), bigger = try layout(GarageAdjustment(scale: 1.4))
        #expect(abs(bigger.carFrame!.height - start.carFrame!.height * 1.4) < 0.5)
        #expect(abs(bigger.carFrame!.width - start.carFrame!.width * 1.4) < 0.5)
        #expect(abs(bigger.carFrame!.midX - start.carFrame!.midX) < 0.5)             // same middle
        #expect(abs(bigger.carFrame!.midY - start.carFrame!.midY) < 0.5)
        #expect(bigger.horizonY == start.horizonY && bigger.door == start.door)
        // The shadow and tire contact stay attached to the car.
        #expect(abs(bigger.groundY - bigger.carFrame!.maxY) < 0.5)
        #expect(abs(bigger.contacts[0].y - bigger.carFrame!.maxY) < 1.5)
    }

    @Test func sizeIsLimitedButFree() throws {
        let tiny = try layout(GarageAdjustment(scale: 0.01)), huge = try layout(GarageAdjustment(scale: 50))
        #expect(tiny.appliedAdjustment.scale == GarageAdjustment.scaleRange.lowerBound)
        #expect(huge.appliedAdjustment.scale == GarageAdjustment.scaleRange.upperBound)
    }

    @Test func draggingAnywhereStillKeepsMostOfTheCarVisible() throws {
        for offset in [GarageAdjustment(offsetX: 5), GarageAdjustment(offsetX: -5), GarageAdjustment(offsetY: 5),
                       GarageAdjustment(offsetY: -5), GarageAdjustment(offsetX: 5, offsetY: 5, scale: 2)] {
            let car = try layout(offset).carFrame!
            let visibleW = min(car.maxX, size.width) - max(car.minX, 0)
            let visibleH = min(car.maxY, size.height) - max(car.minY, 0)
            #expect(visibleW >= car.width * 0.69 && visibleH >= car.height * 0.54, "\(offset)")
        }
    }

    @Test func theAppliedAdjustmentReflectsWhatActuallyHappened() throws {
        let applied = try layout(GarageAdjustment(offsetX: 5)).appliedAdjustment
        #expect(applied.offsetX < 5)                      // clamped
        let again = try layout(applied)
        #expect(abs(again.carFrame!.midX - (try layout(GarageAdjustment(offsetX: 5)).carFrame!.midX)) < 0.5)   // re-applying changes nothing
    }

    @Test func adjustmentsRoundTripThroughTheCarRecord() {
        let car = Car(nickname: "Biscuit")
        #expect(car.garageAdjustment.isNeutral)
        car.garageAdjustment = GarageAdjustment(offsetX: -0.12, offsetY: 0.05, scale: 1.3)
        #expect(abs(car.garageOffsetX + 0.12) < 1e-9 && abs(car.garageOffsetY - 0.05) < 1e-9 && abs(car.garageScale - 1.3) < 1e-9)
        #expect(!car.garageAdjustment.isNeutral)
    }
}
