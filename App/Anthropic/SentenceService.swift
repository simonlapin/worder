import Foundation
import Observation
import SwiftData
import WorderCore

/// Client abstraction the service depends on, mockable in tests.
protocol SentenceGenerating: Sendable {
    func generateSentences(word: String, translations: [String]) async throws -> [GeneratedSentence]
}

extension AnthropicClient: SentenceGenerating {
    func generateSentences(word: String, translations: [String]) async throws -> [GeneratedSentence] {
        try await send(SentenceGenerationRequest(word: word, translations: translations)).sentences
    }
}

/// Fills `CachedSentence` for words already in learning that have no cached
/// sentences yet. Runs in the background (app start, session end) in small
/// batches; API unavailability never blocks studying — failures only surface
/// as a status in Settings.
@MainActor
@Observable
final class SentenceService {
    enum Status: Equatable {
        case idle
        /// No API key stored — generation is off, the app stays fully offline.
        case keyMissing
        case running(done: Int, total: Int)
        case finished(wordsFilled: Int)
        case failed(String)
    }

    static let defaultBatchLimit = 10

    private let context: ModelContext
    private let keyStore: any APIKeyStore
    private let makeGenerator: (String) -> any SentenceGenerating
    private let picker = ContextSentencePicker()

    private(set) var status: Status = .idle

    init(
        context: ModelContext,
        keyStore: any APIKeyStore,
        makeGenerator: @escaping (String) -> any SentenceGenerating = { AnthropicClient(apiKey: $0) }
    ) {
        self.context = context
        self.keyStore = keyStore
        self.makeGenerator = makeGenerator
    }

    /// Generates sentences for up to `batchLimit` candidate words.
    /// Persists after every word, so an interrupted run loses nothing.
    func generateMissingSentences(batchLimit: Int = SentenceService.defaultBatchLimit, now: Date = .now) async {
        if case .running = status { return }

        let key: String?
        do {
            key = try keyStore.readAPIKey()
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        guard let key else {
            status = .keyMissing
            return
        }

        let candidates: [Word]
        do {
            candidates = try fetchCandidates(limit: batchLimit)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        guard !candidates.isEmpty else {
            status = .finished(wordsFilled: 0)
            return
        }

        let generator = makeGenerator(key)
        var filled = 0
        for (index, word) in candidates.enumerated() {
            status = .running(done: index, total: candidates.count)
            do {
                let generated = try await generator.generateSentences(
                    word: word.text,
                    translations: word.translations
                )
                if store(generated, for: word, now: now) {
                    try context.save()
                    filled += 1
                }
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }
        status = .finished(wordsFilled: filled)
    }

    /// Words already introduced (any direction past `new`) with no cached
    /// sentences yet, oldest first.
    private func fetchCandidates(limit: Int) throws -> [Word] {
        let words = try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
        return Array(
            words
                .filter { word in
                    word.sentences.isEmpty
                        && word.directionStates.contains { $0.state != .new }
                }
                .prefix(limit)
        )
    }

    /// Keeps only sentences usable by the context exercise (exact word form
    /// present, non-empty translation). Returns true if anything was cached.
    private func store(_ generated: [GeneratedSentence], for word: Word, now: Date) -> Bool {
        let usable = generated.filter { sentence in
            let trimmedRu = sentence.ru.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRu.isEmpty else { return false }
            return picker.hasUsableSentence(
                wordText: word.text,
                sentences: [WordBatchFile.Sentence(en: sentence.en, ru: sentence.ru)]
            )
        }
        guard !usable.isEmpty else { return false }
        for sentence in usable {
            let cached = CachedSentence(en: sentence.en, ru: sentence.ru, createdAt: now)
            context.insert(cached)
            cached.word = word
        }
        return true
    }
}
