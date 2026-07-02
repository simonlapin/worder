import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
struct BackupViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "ring", "translations": ["кольцо", "звонить"]}
        ]
    }
    """.utf8)

    private func makeContext(populated: Bool) throws -> ModelContext {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        if populated {
            try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)
        }
        return context
    }

    private func makeSettings(limit: Int = 20) -> AppSettings {
        let suiteName = "BackupViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.dailyNewWordLimit = limit
        return settings
    }

    @Test func exportProducesDecodableBackupWithSettings() throws {
        let context = try makeContext(populated: true)
        let model = BackupViewModel(context: context, settings: makeSettings(limit: 7))

        let data = try #require(model.makeExportData(now: now))
        #expect(model.exportFailureMessage == nil)

        let backup = try StateImporter().decode(data)
        #expect(backup.settings.dailyNewWordLimit == 7)
        #expect(backup.batches.flatMap(\.words).count == 2)
    }

    @Test func importIntoEmptyDatabaseRestoresImmediately() throws {
        let source = try makeContext(populated: true)
        let sourceModel = BackupViewModel(context: source, settings: makeSettings(limit: 5))
        let data = try #require(sourceModel.makeExportData(now: now))

        let target = try makeContext(populated: false)
        let settings = makeSettings(limit: 20)
        let model = BackupViewModel(context: target, settings: settings)
        model.beginImport(data: data)

        #expect(model.importPhase == .success(restoredWords: 2))
        #expect(settings.dailyNewWordLimit == 5)
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == 2)
    }

    @Test func importIntoPopulatedDatabaseAsksForConfirmationFirst() throws {
        let source = try makeContext(populated: true)
        let data = try #require(BackupViewModel(context: source, settings: makeSettings()).makeExportData(now: now))

        let target = try makeContext(populated: true)
        let model = BackupViewModel(context: target, settings: makeSettings())
        model.beginImport(data: data)

        #expect(model.importPhase == .needsConfirmation)
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == 2)

        model.confirmOverwrite()
        #expect(model.importPhase == .success(restoredWords: 2))
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == 2)
    }

    @Test func cancellingConfirmationKeepsExistingData() throws {
        let source = try makeContext(populated: true)
        let data = try #require(BackupViewModel(context: source, settings: makeSettings()).makeExportData(now: now))

        let target = try makeContext(populated: true)
        let existingBefore = try target.fetchCount(FetchDescriptor<Word>())
        let model = BackupViewModel(context: target, settings: makeSettings())
        model.beginImport(data: data)
        model.cancelImport()

        #expect(model.importPhase == .idle)
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == existingBefore)

        model.confirmOverwrite()
        #expect(model.importPhase == .idle)
    }

    @Test func invalidBackupFileFailsWithoutTouchingData() throws {
        let target = try makeContext(populated: true)
        let model = BackupViewModel(context: target, settings: makeSettings())
        model.beginImport(data: Data("garbage".utf8))

        guard case .failure = model.importPhase else {
            Issue.record("expected .failure, got \(String(describing: model.importPhase))")
            return
        }
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == 2)
    }
}
