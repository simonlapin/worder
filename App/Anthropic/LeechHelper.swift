import Foundation
import Observation
import SwiftData
import WorderCore

struct LeechHintResponse: Decodable, Equatable, Sendable {
    let hint: String
}

/// Asks for a short Russian hint for a word the learner keeps failing:
/// how it differs from confusable words, or a mnemonic.
struct LeechHintRequest: AnthropicRequest {
    typealias Response = LeechHintResponse

    static let model = "claude-haiku-4-5"
    static let maxTokens = 512

    let word: String
    let translations: [String]
    /// Dictionary words sharing a translation with this word.
    let confusableWords: [String]

    var body: MessagesRequestBody {
        MessagesRequestBody(
            model: Self.model,
            maxTokens: Self.maxTokens,
            messages: [.init(role: "user", content: prompt)],
            outputConfig: .init(format: .init(type: "json_schema", schema: Self.schema))
        )
    }

    private var prompt: String {
        let confusablePart = confusableWords.isEmpty
            ? ""
            : " The learner may be confusing it with: \(confusableWords.joined(separator: ", ")) — explain the difference."
        return """
        A Russian-speaking learner keeps forgetting the English word "\(word)" \
        (Russian: \(translations.joined(separator: ", "))).\(confusablePart) \
        Write a SHORT memorable hint in Russian, 1-3 sentences: a mnemonic, \
        etymology, or vivid association that helps remember this word. \
        Plain text, no markdown.
        """
    }

    private static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "hint": .object(["type": .string("string")]),
        ]),
        "required": .array([.string("hint")]),
        "additionalProperties": .bool(false),
    ])
}

/// Client abstraction, mockable in tests.
protocol LeechHintGenerating: Sendable {
    func generateLeechHint(word: String, translations: [String], confusableWords: [String]) async throws -> String
}

extension AnthropicClient: LeechHintGenerating {
    func generateLeechHint(word: String, translations: [String], confusableWords: [String]) async throws -> String {
        try await send(LeechHintRequest(
            word: word,
            translations: translations,
            confusableWords: confusableWords
        )).hint
    }
}

/// Fills `Word.leechHint` for flagged leeches that have none yet. Without an
/// API key leeches stay plainly flagged — the app never depends on hints.
@MainActor
@Observable
final class LeechHelper {
    static let defaultBatchLimit = 5
    static let maxConfusables = 4

    private let context: ModelContext
    private let keyStore: any APIKeyStore
    private let makeGenerator: (String) -> any LeechHintGenerating

    private(set) var lastFailureMessage: String?

    init(
        context: ModelContext,
        keyStore: any APIKeyStore,
        makeGenerator: @escaping (String) -> any LeechHintGenerating = { AnthropicClient(apiKey: $0) }
    ) {
        self.context = context
        self.keyStore = keyStore
        self.makeGenerator = makeGenerator
    }

    /// Generates hints for up to `batchLimit` leeches without one.
    /// Persists after every word; failures stop the run silently for the UI.
    func fillMissingHints(batchLimit: Int = LeechHelper.defaultBatchLimit) async {
        let key: String?
        do {
            key = try keyStore.readAPIKey()
        } catch {
            lastFailureMessage = error.localizedDescription
            return
        }
        guard let key else { return }

        let leeches: [Word]
        let index: TranslationIndex
        do {
            leeches = Array(
                try context.fetch(FetchDescriptor<Word>(
                    predicate: #Predicate { $0.isLeech && $0.leechHint == nil },
                    sortBy: [SortDescriptor(\.wordId)]
                ))
                .prefix(batchLimit)
            )
            guard !leeches.isEmpty else { return }
            index = try TranslationIndex(context: context)
        } catch {
            lastFailureMessage = error.localizedDescription
            return
        }

        let generator = makeGenerator(key)
        for word in leeches {
            do {
                let hint = try await generator.generateLeechHint(
                    word: word.text,
                    translations: word.translations,
                    confusableWords: confusables(of: word, in: index)
                )
                let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                word.leechHint = trimmed
                try context.save()
                lastFailureMessage = nil
            } catch {
                lastFailureMessage = error.localizedDescription
                return
            }
        }
    }

    private func confusables(of word: Word, in index: TranslationIndex) -> [String] {
        let normalizedSelf = TranslationIndex.normalize(word.text)
        let others = word.translations
            .reduce(into: Set<String>()) { $0.formUnion(index.englishWords(for: $1)) }
            .filter { TranslationIndex.normalize($0) != normalizedSelf }
        return Array(others.sorted().prefix(Self.maxConfusables))
    }
}
