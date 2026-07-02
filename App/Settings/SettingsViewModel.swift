import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let store: any APIKeyStore

    var keyInput = ""
    private(set) var hasStoredKey = false
    private(set) var errorMessage: String?

    var canSaveKey: Bool {
        !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(store: any APIKeyStore) {
        self.store = store
    }

    /// Only checks presence — the key value is never exposed to the UI.
    func refresh() {
        do {
            hasStoredKey = try store.readAPIKey() != nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.saveAPIKey(trimmed)
            keyInput = ""
            hasStoredKey = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteKey() {
        do {
            try store.deleteAPIKey()
            hasStoredKey = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
