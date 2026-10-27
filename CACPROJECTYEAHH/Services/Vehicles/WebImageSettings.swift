import Foundation
import Observation

/// The user's key for web image search, and whether to use it. The key lives in the Keychain, never in source code.
/// For a released app, run searches through your own server so no key ships inside the app.
@Observable
final class WebImageSettings {
    static let shared = WebImageSettings()
    private static let keyAccount = "brave.imageSearchKey"
    private static let enabledKey = "lot.garage.webSearchEnabled"

    private(set) var hasKey: Bool
    private(set) var isEnabled: Bool

    private init() {
        hasKey = KeychainStore.read(Self.keyAccount) != nil || Self.environmentKey != nil
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Developers can set `BRAVE_SEARCH_API_KEY` in the Xcode scheme instead of saving a key.
    private static var environmentKey: String? {
        let value = ProcessInfo.processInfo.environment["BRAVE_SEARCH_API_KEY"]
        return (value?.isEmpty == false) ? value : nil
    }

    var apiKey: String? { KeychainStore.read(Self.keyAccount) ?? Self.environmentKey }

    /// True when web search will actually be tried.
    var isActive: Bool { hasKey && isEnabled }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.write(trimmed, for: Self.keyAccount)
        hasKey = true
    }

    func removeKey() {
        KeychainStore.delete(Self.keyAccount)
        hasKey = Self.environmentKey != nil
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        isEnabled = on
    }
}
