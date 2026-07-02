import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
final class MockLeechHintGenerator: LeechHintGenerating {
    var hints: [String: String] = [:]
    var failure: (word: String, error: AnthropicClientError)?
    private(set) var calls: [(word: String, confusables: [String])] = []

    nonisolated func generateLeechHint(
        word: String,
        translations: [String],
        confusableWords: [String]
    ) async throws -> String {
        try await record(word: word, confusables: confusableWords)
    }

    private func record(word: String, confusables: [String]) throws -> String {
        calls.append((word, confusables))
        if let failure, failure.word == word {
            throw failure.error
        }
        return hints[word] ?? ""
    }
}

@MainActor
struct LeechHelperTests {
    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "store", "translations": ["магазин"]},
            {"id": 3, "word": "dog", "translations": ["собака"]}
        ]
    }
    """.utf8)

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeFixture(leechWordIds: [Int]) throws -> (ModelContainer, ModelContext) {
        let container = try WorderModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: t0)
        for word in try context.fetch(FetchDescriptor<Word>()) where leechWordIds.contains(word.wordId) {
            word.isLeech = true
        }
        try context.save()
        return (container, context)
    }

    private func makeHelper(
        context: ModelContext,
        generator: MockLeechHintGenerator,
        storedKey: String? = "sk-ant-x"
    ) -> LeechHelper {
        let store = InMemoryAPIKeyStore()
        store.storedKey = storedKey
        return LeechHelper(context: context, keyStore: store) { _ in generator }
    }

    @Test func withoutKeyLeechesStayPlainlyFlagged() async throws {
        let (_, context) = try makeFixture(leechWordIds: [1])
        let generator = MockLeechHintGenerator()
        let helper = makeHelper(context: context, generator: generator, storedKey: nil)

        await helper.fillMissingHints()

        #expect(generator.calls.isEmpty)
        let shop = try #require(context.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        #expect(shop.isLeech)
        #expect(shop.leechHint == nil)
    }

    @Test func generatesHintsOnlyForLeechesWithoutOneAndPassesConfusables() async throws {
        let (container, context) = try makeFixture(leechWordIds: [1])
        let generator = MockLeechHintGenerator()
        generator.hints = ["shop": "  Шоп — шоппинг происходит в магазине.  "]
        let helper = makeHelper(context: context, generator: generator)

        await helper.fillMissingHints()

        #expect(generator.calls.count == 1)
        #expect(generator.calls.first?.word == "shop")
        #expect(generator.calls.first?.confusables == ["store"])

        let shop = try #require(ModelContext(container).fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        #expect(shop.leechHint == "Шоп — шоппинг происходит в магазине.")
        #expect(helper.lastFailureMessage == nil)

        await helper.fillMissingHints()
        #expect(generator.calls.count == 1)
    }

    @Test func failureStopsRunAndKeepsEarlierHints() async throws {
        let (container, context) = try makeFixture(leechWordIds: [1, 3])
        let generator = MockLeechHintGenerator()
        generator.hints = ["shop": "Подсказка про магазин."]
        generator.failure = (word: "dog", error: .apiError(status: 500, type: nil, message: "boom"))
        let helper = makeHelper(context: context, generator: generator)

        await helper.fillMissingHints()

        #expect(helper.lastFailureMessage != nil)
        let words = try ModelContext(container).fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
        #expect(words.first { $0.wordId == 1 }?.leechHint == "Подсказка про магазин.")
        #expect(words.first { $0.wordId == 3 }?.leechHint == nil)
    }

    @Test func emptyHintIsNotCached() async throws {
        let (_, context) = try makeFixture(leechWordIds: [3])
        let generator = MockLeechHintGenerator()
        generator.hints = ["dog": "   "]
        let helper = makeHelper(context: context, generator: generator)

        await helper.fillMissingHints()

        let dog = try #require(context.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 3 }
        )).first)
        #expect(dog.leechHint == nil)
    }
}
