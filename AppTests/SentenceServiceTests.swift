import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
final class MockSentenceGenerator: SentenceGenerating {
    var responses: [String: [GeneratedSentence]] = [:]
    var failure: (word: String, error: AnthropicClientError)?
    private(set) var requestedWords: [String] = []

    nonisolated func generateSentences(word: String, translations: [String]) async throws -> [GeneratedSentence] {
        try await record(word: word)
    }

    private func record(word: String) throws -> [GeneratedSentence] {
        requestedWords.append(word)
        if let failure, failure.word == word {
            throw failure.error
        }
        return responses[word] ?? []
    }
}

@MainActor
struct SentenceServiceTests {
    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "dog", "translations": ["собака"]},
            {"id": 3, "word": "cat", "translations": ["кошка"]}
        ]
    }
    """.utf8)

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeFixture(startedWordIds: [Int]) throws -> (ModelContainer, ModelContext) {
        let container = try WorderModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: t0)
        for word in try context.fetch(FetchDescriptor<Word>()) where startedWordIds.contains(word.wordId) {
            word.directionState(for: .enToRu)?.state = .learning
        }
        try context.save()
        return (container, context)
    }

    private func makeService(
        context: ModelContext,
        generator: MockSentenceGenerator,
        storedKey: String? = "sk-ant-x"
    ) -> SentenceService {
        let store = InMemoryAPIKeyStore()
        store.storedKey = storedKey
        return SentenceService(context: context, keyStore: store) { _ in generator }
    }

    @Test func withoutKeyDoesNothing() async throws {
        let (_, context) = try makeFixture(startedWordIds: [1])
        let generator = MockSentenceGenerator()
        let service = makeService(context: context, generator: generator, storedKey: nil)

        await service.generateMissingSentences(now: t0)

        #expect(service.status == .keyMissing)
        #expect(generator.requestedWords.isEmpty)
    }

    @Test func generatesOnlyForStartedWordsWithoutSentences() async throws {
        let (container, context) = try makeFixture(startedWordIds: [1, 2])
        let generator = MockSentenceGenerator()
        generator.responses = [
            "shop": [GeneratedSentence(en: "I like this shop.", ru: "Мне нравится этот магазин.")],
            "dog": [GeneratedSentence(en: "My dog is big.", ru: "Моя собака большая.")],
        ]
        let service = makeService(context: context, generator: generator)

        await service.generateMissingSentences(now: t0)

        #expect(service.status == .finished(wordsFilled: 2))
        #expect(generator.requestedWords == ["shop", "dog"])

        let other = ModelContext(container)
        let cached = try other.fetch(FetchDescriptor<CachedSentence>())
        #expect(cached.count == 2)
        let shop = try #require(other.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        #expect(shop.sentences.map(\.en) == ["I like this shop."])
    }

    @Test func secondRunGeneratesNothing() async throws {
        let (_, context) = try makeFixture(startedWordIds: [1])
        let generator = MockSentenceGenerator()
        generator.responses = [
            "shop": [GeneratedSentence(en: "I like this shop.", ru: "Мне нравится этот магазин.")]
        ]
        let service = makeService(context: context, generator: generator)

        await service.generateMissingSentences(now: t0)
        await service.generateMissingSentences(now: t0)

        #expect(service.status == .finished(wordsFilled: 0))
        #expect(generator.requestedWords == ["shop"])
    }

    @Test func failureKeepsEarlierResultsAndSurfacesInStatus() async throws {
        let (container, context) = try makeFixture(startedWordIds: [1, 2])
        let generator = MockSentenceGenerator()
        generator.responses = [
            "shop": [GeneratedSentence(en: "I like this shop.", ru: "Мне нравится этот магазин.")]
        ]
        generator.failure = (word: "dog", error: .apiError(status: 529, type: "overloaded_error", message: "busy"))
        let service = makeService(context: context, generator: generator)

        await service.generateMissingSentences(now: t0)

        guard case .failed = service.status else {
            Issue.record("expected failed status, got \(service.status)")
            return
        }
        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedSentence>())
        #expect(cached.map(\.en) == ["I like this shop."])
    }

    @Test func sentencesWithoutExactWordFormAreRejected() async throws {
        let (container, context) = try makeFixture(startedWordIds: [1])
        let generator = MockSentenceGenerator()
        generator.responses = [
            "shop": [
                GeneratedSentence(en: "Two shops are closed.", ru: "Два магазина закрыты."),
                GeneratedSentence(en: "The shop is open.", ru: "Магазин открыт."),
                GeneratedSentence(en: "A shop sells things.", ru: "   "),
            ]
        ]
        let service = makeService(context: context, generator: generator)

        await service.generateMissingSentences(now: t0)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedSentence>())
        #expect(cached.map(\.en) == ["The shop is open."])
        #expect(service.status == .finished(wordsFilled: 1))
    }

    @Test func batchLimitBoundsOneRun() async throws {
        let (_, context) = try makeFixture(startedWordIds: [1, 2, 3])
        let generator = MockSentenceGenerator()
        generator.responses = [
            "shop": [GeneratedSentence(en: "I like this shop.", ru: "Мне нравится этот магазин.")],
            "dog": [GeneratedSentence(en: "My dog is big.", ru: "Моя собака большая.")],
            "cat": [GeneratedSentence(en: "The cat sleeps.", ru: "Кот спит.")],
        ]
        let service = makeService(context: context, generator: generator)

        await service.generateMissingSentences(batchLimit: 2, now: t0)

        #expect(generator.requestedWords == ["shop", "dog"])
        #expect(service.status == .finished(wordsFilled: 2))

        await service.generateMissingSentences(batchLimit: 2, now: t0)
        #expect(generator.requestedWords == ["shop", "dog", "cat"])
    }
}
