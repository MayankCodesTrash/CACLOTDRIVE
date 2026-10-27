import SwiftUI

/// Runs one AI parking check: redact, send, decode. Holds the UI state for it.
@MainActor
@Observable
final class ParkingAICoordinator {
    enum Phase: Equatable {
        case idle
        case preparing
        case asking
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var regionsBlurred = 0

    var isBusy: Bool { phase == .preparing || phase == .asking }

    func run(photo: Data, coverBoxes: [PlateBox] = [], analyzer: ParkingAnalyzing? = nil) async -> ParkingAnalysis? {
        let settings = AISettings.shared
        guard let image = UIImage(data: photo) else {
            phase = .failed(ParkingAnalysisError.badImage.localizedDescription)
            return nil
        }
        phase = .preparing
        let redacted = await PrivacyRedactor.redact(image, coverBoxes: coverBoxes)
        regionsBlurred = redacted.regionsBlurred
        guard let jpeg = redacted.image.jpegData(compressionQuality: 0.8) else {
            phase = .failed(ParkingAnalysisError.badImage.localizedDescription)
            return nil
        }

        phase = .asking
        let service = analyzer ?? GeminiParkingAnalyzer(apiKey: settings.apiKey, model: settings.model)
        do {
            let analysis = try await service.analyze(jpeg: jpeg)
            phase = .done
            return analysis
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }
}
