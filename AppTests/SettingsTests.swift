import Foundation
import Testing
@testable import Worder

@MainActor
final class InMemoryAPIKeyStore: APIKeyStore {
    var storedKey: String?
    var failure: KeychainError?

    func readAPIKey() throws -> String? {
        if let failure { throw failure }
        return storedKey
    }

    func saveAPIKey(_ key: String) throws {
        if let failure { throw failure }
        storedKey = key
    }

    func deleteAPIKey() throws {
        if let failure { throw failure }
        storedKey = nil
    }
}

@MainActor
struct KeychainStoreTests {
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "dev.lsa.worder.tests")
    }

    @Test func roundTripSaveReadDelete() throws {
        let store = makeStore()
        try store.deleteAPIKey()

        #expect(try store.readAPIKey() == nil)

        try store.saveAPIKey("sk-ant-test-123")
        #expect(try store.readAPIKey() == "sk-ant-test-123")

        try store.saveAPIKey("sk-ant-overwritten")
        #expect(try store.readAPIKey() == "sk-ant-overwritten")

        try store.deleteAPIKey()
        #expect(try store.readAPIKey() == nil)
    }

    @Test func deletingMissingKeyDoesNotThrow() throws {
        let store = makeStore()
        try store.deleteAPIKey()
        try store.deleteAPIKey()
    }
}

@MainActor
struct SettingsViewModelTests {
    @Test func refreshReportsKeyPresence() {
        let store = InMemoryAPIKeyStore()
        let model = SettingsViewModel(store: store)

        model.refresh()
        #expect(!model.hasStoredKey)

        store.storedKey = "sk-ant-x"
        model.refresh()
        #expect(model.hasStoredKey)
    }

    @Test func saveTrimsInputAndClearsField() {
        let store = InMemoryAPIKeyStore()
        let model = SettingsViewModel(store: store)

        model.keyInput = "   "
        #expect(!model.canSaveKey)
        model.saveKey()
        #expect(store.storedKey == nil)

        model.keyInput = "  sk-ant-abc  "
        #expect(model.canSaveKey)
        model.saveKey()
        #expect(store.storedKey == "sk-ant-abc")
        #expect(model.keyInput.isEmpty)
        #expect(model.hasStoredKey)
    }

    @Test func deleteClearsStoredKey() {
        let store = InMemoryAPIKeyStore()
        store.storedKey = "sk-ant-x"
        let model = SettingsViewModel(store: store)
        model.refresh()

        model.deleteKey()
        #expect(store.storedKey == nil)
        #expect(!model.hasStoredKey)
    }

    @Test func storeFailureSurfacesAsErrorMessage() {
        let store = InMemoryAPIKeyStore()
        store.failure = KeychainError(operation: "read", status: -1)
        let model = SettingsViewModel(store: store)

        model.refresh()
        #expect(model.errorMessage != nil)

        store.failure = nil
        model.refresh()
        #expect(model.errorMessage == nil)
    }
}

@MainActor
struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func defaultsToTwentyNewWordsPerDay() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.dailyNewWordLimit == 20)
    }

    @Test func limitPersistsAcrossInstances() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults).dailyNewWordLimit = 5
        #expect(AppSettings(defaults: defaults).dailyNewWordLimit == 5)
    }

    @Test func limitIsClampedToAllowedRange() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.dailyNewWordLimit = 999
        #expect(settings.dailyNewWordLimit == 50)
        settings.dailyNewWordLimit = -3
        #expect(settings.dailyNewWordLimit == 0)

        defaults.set(200, forKey: AppSettings.dailyNewWordLimitKey)
        #expect(AppSettings(defaults: defaults).dailyNewWordLimit == 50)
    }
}
