import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)

@Suite struct TranslationIndexNormalizationTests {
    @Test func normalizesCaseYoAndWhitespace() {
        #expect(TranslationIndex.normalize("  Магазин ") == "магазин")
        #expect(TranslationIndex.normalize("самолёт") == "самолет")
        #expect(TranslationIndex.normalize("Самолет") == "самолет")
        #expect(TranslationIndex.normalize("иметь   в\tвиду") == "иметь в виду")
    }

    @Test func lookupIsNormalizationInsensitive() {
        var index = TranslationIndex()
        index.add(word: "plane", translations: ["самолёт"])
        index.add(word: "airplane", translations: ["самолет"])

        #expect(index.englishWords(for: "САМОЛЁТ") == ["plane", "airplane"])
        #expect(index.englishWords(for: " самолет ") == ["plane", "airplane"])
        #expect(index.englishWords(for: "поезд").isEmpty)
    }

    @Test func multiValuedWordIndexesEveryTranslation() {
        var index = TranslationIndex()
        index.add(word: "ring", translations: ["кольцо", "звонить"])

        #expect(index.englishWords(for: "кольцо") == ["ring"])
        #expect(index.englishWords(for: "звонить") == ["ring"])
    }
}

@Suite struct TranslationIndexDatabaseTests {
    private func importCore1500(into context: ModelContext) throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WorderCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // WorderCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("data/core-1500.json")
        try BatchImporter(context: context).importBatch(from: Data(contentsOf: url), now: now)
    }

    @Test func indexesCore1500Synonyms() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        try importCore1500(into: context)
        let index = try TranslationIndex(context: context)

        #expect(index.englishWords(for: "магазин") == ["shop", "store"])
        #expect(index.englishWords(for: "самолёт") == ["plane", "airplane"])
        #expect(index.englishWords(for: "машина") == ["car", "machine"])
        #expect(index.englishWords(for: "кольцо") == ["ring"])
    }

    @Test func rebuildAfterImportPicksUpNewWords() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let importer = BatchImporter(context: context)
        try importer.importBatch(
            WordBatchFile(batchId: "b", title: "t", words: [
                .init(id: 1, word: "shop", translations: ["магазин"]),
            ]),
            now: now
        )
        let before = try TranslationIndex(context: context)
        #expect(before.englishWords(for: "магазин") == ["shop"])

        try importer.importBatch(
            WordBatchFile(batchId: "b", title: "t", words: [
                .init(id: 1, word: "shop", translations: ["магазин"]),
                .init(id: 2, word: "store", translations: ["магазин"]),
            ]),
            now: now
        )
        let after = try TranslationIndex(context: context)
        #expect(after.englishWords(for: "магазин") == ["shop", "store"])
    }
}
