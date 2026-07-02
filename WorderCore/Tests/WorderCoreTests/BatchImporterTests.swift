import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let later = now.addingTimeInterval(86_400)

private func makeContext() throws -> ModelContext {
    ModelContext(try WorderModelContainer.make(inMemory: true))
}

private func batchFile(words: [WordBatchFile.Entry]) -> WordBatchFile {
    WordBatchFile(batchId: "test-batch", title: "Test batch", words: words)
}

private let initialFile = batchFile(words: [
    .init(id: 1, word: "shop", translations: ["магазин"]),
    .init(id: 2, word: "ring", translations: ["кольцо", "звонить"], note: "сущ./гл."),
])

@Suite struct BatchImporterFreshImportTests {
    @Test func createsBatchWordsAndDirectionStates() throws {
        let context = try makeContext()
        let summary = try BatchImporter(context: context).importBatch(initialFile, now: now)

        #expect(summary == BatchImportSummary(
            batchId: "test-batch", insertedWords: 2, updatedWords: 0, unchangedWords: 0
        ))

        let batches = try context.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 1)
        #expect(batches[0].title == "Test batch")
        #expect(batches[0].importedAt == now)

        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.count == 2)
        let ring = try #require(words.first { $0.text == "ring" })
        #expect(ring.translations == ["кольцо", "звонить"])
        #expect(ring.note == "сущ./гл.")
        #expect(ring.batch?.batchId == "test-batch")

        let states = try context.fetch(FetchDescriptor<DirectionState>())
        #expect(states.count == 4)
        #expect(states.allSatisfy { $0.state == .new && $0.due == now && $0.reps == 0 })
        #expect(Set(ring.directionStates.map(\.direction)) == Set(Direction.allCases))
    }

    @Test func importsFromRawData() throws {
        let context = try makeContext()
        let json = """
        {"schemaVersion": 1, "batchId": "b", "title": "t",
         "words": [{"id": 1, "word": "yes", "translations": ["да"]}]}
        """
        let summary = try BatchImporter(context: context).importBatch(from: Data(json.utf8), now: now)
        #expect(summary.insertedWords == 1)
    }

    @Test func rejectsInvalidDataWithTypedError() throws {
        let context = try makeContext()
        let json = """
        {"schemaVersion": 1, "batchId": "b", "title": "t",
         "words": [{"id": 7, "word": "yes", "translations": []}]}
        """
        #expect(throws: WordBatchFileError.emptyTranslations(id: 7, word: "yes")) {
            try BatchImporter(context: context).importBatch(from: Data(json.utf8), now: now)
        }
        #expect(try context.fetch(FetchDescriptor<Batch>()).isEmpty)
    }
}

@Suite struct BatchImporterReimportTests {
    @Test func identicalReimportCreatesNoDuplicatesAndKeepsProgress() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let ring = try #require(try context.fetch(FetchDescriptor<Word>()).first { $0.text == "ring" })
        let enToRu = try #require(ring.directionState(for: .enToRu))
        enToRu.state = .review
        enToRu.stability = 10
        enToRu.due = later
        enToRu.reps = 3
        let log = ReviewLog(reviewedAt: now, direction: .enToRu, grade: .good)
        context.insert(log)
        log.word = ring
        try context.save()

        let summary = try importer.importBatch(initialFile, now: later)

        #expect(summary == BatchImportSummary(
            batchId: "test-batch", insertedWords: 0, updatedWords: 0, unchangedWords: 2
        ))
        #expect(try context.fetch(FetchDescriptor<Batch>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).count == 4)

        let reloaded = try #require(ring.directionState(for: .enToRu))
        #expect(reloaded.state == .review)
        #expect(reloaded.stability == 10)
        #expect(reloaded.due == later)
        #expect(reloaded.reps == 3)
        #expect(ring.reviewLogs.count == 1)
    }

    @Test func updatedTranslationIsAppliedWithoutTouchingState() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let shop = try #require(try context.fetch(FetchDescriptor<Word>()).first { $0.text == "shop" })
        let ruToEn = try #require(shop.directionState(for: .ruToEn))
        ruToEn.reps = 5
        try context.save()

        let updatedFile = batchFile(words: [
            .init(id: 1, word: "shop", translations: ["магазин", "лавка"], note: "разг."),
            .init(id: 2, word: "ring", translations: ["кольцо", "звонить"], note: "сущ./гл."),
        ])
        let summary = try importer.importBatch(updatedFile, now: later)

        #expect(summary.updatedWords == 1)
        #expect(summary.unchangedWords == 1)
        #expect(shop.translations == ["магазин", "лавка"])
        #expect(shop.note == "разг.")
        #expect(try #require(shop.directionState(for: .ruToEn)).reps == 5)
    }

    @Test func newWordInExistingBatchIsInserted() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let extendedFile = batchFile(words: initialFile.words + [
            .init(id: 3, word: "store", translations: ["магазин"]),
        ])
        let summary = try importer.importBatch(extendedFile, now: later)

        #expect(summary.insertedWords == 1)
        #expect(summary.unchangedWords == 2)
        let store = try #require(try context.fetch(FetchDescriptor<Word>()).first { $0.text == "store" })
        #expect(store.directionStates.count == 2)
        #expect(store.directionStates.allSatisfy { $0.due == later && $0.state == .new })
    }

    @Test func wordMissingFromNewerFileIsKept() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let shrunkFile = batchFile(words: [initialFile.words[0]])
        let summary = try importer.importBatch(shrunkFile, now: later)

        #expect(summary == BatchImportSummary(
            batchId: "test-batch", insertedWords: 0, updatedWords: 0, unchangedWords: 1
        ))
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 2)
    }

    @Test func batchMetadataIsRefreshedOnReimport() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let renamed = WordBatchFile(
            batchId: "test-batch", title: "Renamed", category: "core", words: initialFile.words
        )
        try importer.importBatch(renamed, now: later)

        let batch = try #require(try context.fetch(FetchDescriptor<Batch>()).first)
        #expect(batch.title == "Renamed")
        #expect(batch.category == "core")
        #expect(batch.importedAt == now)
    }

    @Test func sameWordIdInDifferentBatchesDoesNotCollide() throws {
        let context = try makeContext()
        let importer = BatchImporter(context: context)
        try importer.importBatch(initialFile, now: now)

        let other = WordBatchFile(batchId: "other-batch", title: "Other", words: [
            .init(id: 1, word: "car", translations: ["машина"]),
        ])
        let summary = try importer.importBatch(other, now: now)

        #expect(summary.insertedWords == 1)
        #expect(try context.fetch(FetchDescriptor<Batch>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 3)
        let shop = try #require(try context.fetch(FetchDescriptor<Word>()).first { $0.text == "shop" })
        #expect(shop.translations == ["магазин"])
    }
}

@Suite struct BatchImporterCore1500Tests {
    @Test func importsRealCore1500Twice() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WorderCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // WorderCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("data/core-1500.json")
        let data = try Data(contentsOf: url)

        let context = try makeContext()
        let importer = BatchImporter(context: context)

        let first = try importer.importBatch(from: data, now: now)
        #expect(first.insertedWords == 1500)

        let second = try importer.importBatch(from: data, now: later)
        #expect(second == BatchImportSummary(
            batchId: first.batchId, insertedWords: 0, updatedWords: 0, unchangedWords: 1500
        ))
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 1500)
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).count == 3000)
    }
}
