import Foundation
import Observation

/// Gemini key, model, and the user's one-time consent to send photos to Google.
/// The key lives in the Keychain. For a Congressional App Challenge prototype it is entered by the
/// person using the app. A shipped app should call Gemini through its own server instead.
@Observable
final class AISettings {
    static let shared = AISettings()
    static let defaultModel = "gemini-3.8-flash"

    private static let keyAccount = "gemini.apiKey"
    private static let consentKey = "lot.ai.parkingConsent"
    private static let modelKey = "lot.ai.model"

    private(set) var hasKey: Bool
    private(set) var hasConsented: Bool
    private(set) var model: String

    private init() {
        hasKey = KeychainStore.read(Self.keyAccount) != nil || Self.environmentKey != nil
        hasConsented = UserDefaults.standard.bool(forKey: Self.consentKey)
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
    }

    /// Lets a developer run with `GEMINI_API_KEY` set in the Xcode scheme, without storing anything.
    private static var environmentKey: String? {
        let value = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        return (value?.isEmpty == false) ? value : nil
    }

    var apiKey: String? { KeychainStore.read(Self.keyAccount) ?? Self.environmentKey }

    /// Returns whether the key really reached the Keychain, so the UI never claims a save that failed.
    @discardableResult
    func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard KeychainStore.write(trimmed, for: Self.keyAccount) else { return false }
        hasKey = true
        return true
    }

    func removeKey() {
        KeychainStore.delete(Self.keyAccount)
        hasKey = Self.environmentKey != nil
    }

    func setConsent(_ granted: Bool) {
        UserDefaults.standard.set(granted, forKey: Self.consentKey)
        hasConsented = granted
    }

    func setModel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmed.isEmpty ? Self.defaultModel : trimmed
        UserDefaults.standard.set(model, forKey: Self.modelKey)
    }
}
