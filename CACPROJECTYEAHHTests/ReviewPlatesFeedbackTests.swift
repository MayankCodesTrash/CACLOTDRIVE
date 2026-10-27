import Testing
import Foundation
import SwiftData
import UIKit
import UserNotifications
@testable import CACPROJECTYEAHH

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Car.self, Drive.self, DrivePhoto.self, ParkingCheck.self,
                         Plan.self, PlanStop.self, PlanCar.self, PlanPerson.self, RideAssignment.self])
    return ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
}

@MainActor
struct DriveReviewTests {
    private func draft() -> TripDraft {
        TripDraft(start: .now.addingTimeInterval(-600), end: .now, distanceMeters: 3000, route: [])
    }

    @Test func detectedAndSimulatedTripsNeedReviewButManualAndSampleDoNot() throws {
        let repo = TripRepository(context: try makeContext())
        #expect(repo.save(draft(), source: .automatic).needsReview)
        #expect(repo.save(draft(), source: .simulated).needsReview)
        #expect(!repo.save(draft(), source: .sample).needsReview)
    }

    @Test func simulatedTripIsNotMarkedAsSampleData() throws {
        let repo = TripRepository(context: try makeContext())
        #expect(!repo.save(draft(), source: .simulated).isDemo)
        #expect(repo.save(draft(), source: .sample).isDemo)
    }

    @Test func answeringReviewClearsTheFlagAndSetsPassenger() throws {
        let repo = TripRepository(context: try makeContext())
        let a = repo.save(draft(), source: .automatic)
        repo.review(a, as: .passenger)
        #expect(a.isPassenger && !a.needsReview)
        let b = repo.save(draft(), source: .automatic)
        repo.review(b, as: .iDrove)
        #expect(!b.isPassenger && !b.needsReview)
    }

    @Test func draftTitleAndDestinationAreKept() throws {
        let repo = TripRepository(context: try makeContext())
        var d = draft(); d.title = "Drive to Hy-Vee"; d.destination = "Hy-Vee"
        let trip = repo.save(d, source: .simulated)
        #expect(trip.title == "Drive to Hy-Vee" && trip.destination == "Hy-Vee")
    }
}

struct TabBarScrubTests {
    @Test func widthSplitsIntoEqualZones() {
        let count = LotTab.allCases.count
        for (i, tab) in LotTab.allCases.enumerated() {
            let x = (CGFloat(i) + 0.5) * 100
            #expect(LotTabBar.tab(atX: x, barWidth: 100 * CGFloat(count)) == tab)
        }
    }

    @Test func fingerPastTheEndsPicksEndTabs() {
        #expect(LotTabBar.tab(atX: -40, barWidth: 300) == LotTab.allCases.first)
        #expect(LotTabBar.tab(atX: 900, barWidth: 300) == LotTab.allCases.last)
        #expect(LotTabBar.tab(atX: 10, barWidth: 0) == nil)
    }
}

struct RouteThinningTests {
    @Test func thinnedKeepsEndsAndLimit() {
        let points = (0..<5000).map { RoutePoint(lat: Double($0), lon: 0) }
        let thin = TripDetectionService.thinned(points, to: 1500)
        #expect(thin.count == 1500)
        #expect(thin.first == points.first && thin.last == points.last)
        #expect(TripDetectionService.thinned(Array(points.prefix(10)), to: 1500).count == 10)
    }
}

@MainActor
struct ParkingPromptTests {
    final class FakeCenter: NotificationScheduling {
        var granted = true
        var added: [UNNotificationRequest] = []
        var categories: Set<UNNotificationCategory> = []
        func requestAuthorization() async -> Bool { granted }
        func add(_ request: UNNotificationRequest) async { added.append(request) }
        func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }
    }

    @Test func contentCarriesTripIDAndCategory() {
        let id = UUID()
        let content = ParkingPromptCenter.content(tripID: id, tripTitle: "Drive to Hy-Vee")
        #expect(content.userInfo[ParkingPromptCenter.tripKey] as? String == id.uuidString)
        #expect(content.categoryIdentifier == ParkingPromptCenter.categoryID)
        #expect(content.body.contains("out of the car"))
    }

    @Test func schedulesOneNotificationWhenAllowed() async {
        let fake = FakeCenter()
        let prompts = ParkingPromptCenter()
        prompts.center = fake
        await prompts.notifyParked(tripID: UUID(), tripTitle: "Test")
        #expect(fake.added.count == 1)
    }

    @Test func schedulesNothingWhenDenied() async {
        let fake = FakeCenter(); fake.granted = false
        let prompts = ParkingPromptCenter()
        prompts.center = fake
        await prompts.notifyParked(tripID: UUID(), tripTitle: "Test")
        #expect(fake.added.isEmpty)
    }

    @Test func registersTakePhotoAction() {
        let category = ParkingPromptCenter.categories.first
        #expect(category?.identifier == ParkingPromptCenter.categoryID)
        #expect(category?.actions.first?.identifier == ParkingPromptCenter.photoActionID)
    }
}

struct PlateCoverTests {
    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 400, height: 300)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let cg = image.cgImage!
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    @Test func boxFromAnyDragDirectionIsNormalizedAndClamped() {
        let box = PlateBox(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 50), in: CGSize(width: 400, height: 500))
        #expect(abs(box.x - 0.25) < 0.001 && abs(box.y - 0.1) < 0.001)
        #expect(abs(box.width - 0.5) < 0.001 && abs(box.height - 0.4) < 0.001)
        let outside = PlateBox(from: CGPoint(x: -50, y: -50), to: CGPoint(x: 900, y: 900), in: CGSize(width: 400, height: 500))
        #expect(outside.x == 0 && outside.y == 0 && outside.width == 1 && outside.height == 1)
    }

    @Test func movingAndResizingStayInsidePhoto() {
        let box = PlateBox(x: 0.5, y: 0.5, width: 0.3, height: 0.2)
        let moved = box.moved(dx: 5, dy: -5)
        #expect(moved.x == 0.7 && moved.y == 0)
        let resized = box.resized(dw: 5, dh: -5)
        #expect(resized.width == 0.5 && resized.height == PlateBox.minimumSide)
    }

    @Test func coveredAreaBecomesSolidBlackAndRestIsKept() {
        let covered = PrivacyRedactor.cover(solidImage(.white), with: [PlateBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5)])
        let inside = pixel(covered, 200, 150)
        #expect(inside.r < 5 && inside.g < 5 && inside.b < 5)
        let outside = pixel(covered, 10, 10)
        #expect(outside.r > 250 && outside.g > 250 && outside.b > 250)
    }

    @Test func fullRedactionKeepsCoveredAreaBlackAndCountsIt() {
        let result = PrivacyRedactor.redactSync(solidImage(.white), coverBoxes: [PlateBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2)], maxDimension: 400)
        let inside = pixel(result.image, 200, 150)
        #expect(inside.r < 10)
        #expect(result.regionsBlurred >= 1)
    }

    @Test func noBoxesReturnsTheSameImage() {
        let image = solidImage(.red)
        #expect(PrivacyRedactor.cover(image, with: []) === image)
    }

    @Test func overlapIgnoresSeparateBoxes() {
        let a = PlateBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        #expect(a.overlaps(PlateBox(x: 0.12, y: 0.11, width: 0.2, height: 0.1)))
        #expect(!a.overlaps(PlateBox(x: 0.6, y: 0.6, width: 0.2, height: 0.1)))
    }
}

// Shares the serialized Gemini suite: all of these tests use the same mocked host.
extension GeminiParkingAnalyzerTests {
    private func connectionSession(status: Int) -> URLSession {
        MockURLProtocol.handlers[MockURLProtocol.geminiHost] = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func connectionAnalyzer(_ status: Int, key: String? = "k") -> GeminiParkingAnalyzer {
        GeminiParkingAnalyzer(apiKey: key, model: "gemini-test", session: connectionSession(status: status))
    }

    @Test func okWhenGoogleReturnsModel() async throws {
        try await connectionAnalyzer(200).testConnection()
        let request = try #require(MockURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test")
        #expect(request.httpMethod == "GET" || request.httpMethod == nil)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "k")
    }

    @Test func mapsFailures() async {
        await #expect(throws: ParkingAnalysisError.invalidKey) { try await connectionAnalyzer(400).testConnection() }
        await #expect(throws: ParkingAnalysisError.invalidKey) { try await connectionAnalyzer(403).testConnection() }
        await #expect(throws: ParkingAnalysisError.modelNotFound("gemini-test")) { try await connectionAnalyzer(404).testConnection() }
        await #expect(throws: ParkingAnalysisError.rateLimited) { try await connectionAnalyzer(429).testConnection() }
        await #expect(throws: ParkingAnalysisError.missingKey) { try await connectionAnalyzer(200, key: nil).testConnection() }
    }
}

@MainActor
struct SampleParkingFeedbackTests {
    @Test func sampleFeedbackImprovesAndIsLabeledSample() {
        let analyses = SampleParking.quality.map { SampleParking.analysis(quality: $0, date: .now) }
        #expect(analyses.allSatisfy { $0.model == SampleParking.modelName && $0.assessable })
        func good(_ a: ParkingAnalysis) -> Int { a.findings.filter { $0.status == .good }.count }
        #expect(good(analyses.first!) == 0)
        #expect(good(analyses.last!) == 3)
        let goods = analyses.map(good)
        #expect(goods == goods.sorted())
    }

    @Test func sampleImagesRender() throws {
        let data = try #require(SampleParking.image(quality: 0.2, seed: 1))
        #expect(UIImage(data: data) != nil)
    }

    @Test func loadingSampleDataAttachesPhotosAndFeedback() throws {
        let context = try makeContext()
        SampleData.load(into: context)
        let checks = try context.fetch(FetchDescriptor<ParkingCheck>())
        #expect(checks.count == 8)
        #expect(checks.allSatisfy { $0.photo != nil && $0.aiAnalysis?.model == "sample" && $0.isDemo })
    }

    @Test func trendComparesEarlyAndLatestFromStoredFeedback() throws {
        let context = try makeContext()
        SampleData.load(into: context)
        let trend = ParkingFeedbackTrend(checks: try context.fetch(FetchDescriptor<ParkingCheck>()))
        #expect(trend.hasTrend && trend.attempts.count == 8)
        let summary = try #require(trend.summary)
        #expect(summary.contains("first 3") && summary.contains("latest 3"))
        let early = trend.attempts.prefix(3).map(\.good).reduce(0, +)
        let recent = trend.attempts.suffix(3).map(\.good).reduce(0, +)
        #expect(recent > early)
    }

    @Test func trendIgnoresChecksWithoutUsableFeedback() throws {
        let context = try makeContext()
        let plain = ParkingCheck(); context.insert(plain)
        var unassessable = SampleParking.analysis(quality: 0.9, date: .now)
        unassessable.assessable = false
        let second = ParkingCheck(); second.aiAnalysis = unassessable; context.insert(second)
        let trend = ParkingFeedbackTrend(checks: [plain, second])
        #expect(trend.attempts.isEmpty && !trend.hasTrend && trend.summary == nil)
    }
}

@MainActor
struct CoveredPhotoReplacementTests {
    @Test func coveredPhotoDiffersFromOriginalAndKeepsFullSize() throws {
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let covered = PrivacyRedactor.cover(original, with: [PlateBox(x: 0.4, y: 0.4, width: 0.2, height: 0.1)])
        let data = try #require(covered.jpegData(compressionQuality: 0.92))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == original.size)
        #expect(data != original.jpegData(compressionQuality: 0.92))
    }
}
