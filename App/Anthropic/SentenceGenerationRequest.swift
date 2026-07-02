import Foundation

struct GeneratedSentence: Decodable, Equatable, Sendable {
    let en: String
    let ru: String
}

struct SentenceGenerationResponse: Decodable, Equatable, Sendable {
    let sentences: [GeneratedSentence]
}

/// Asks for 2–3 short example sentences for one word. The sentences must
/// contain the word in its exact written form — the context exercise masks
/// exact occurrences only (see ContextSentencePicker).
struct SentenceGenerationRequest: AnthropicRequest {
    typealias Response = SentenceGenerationResponse

    static let model = "claude-haiku-4-5"
    static let maxTokens = 1024

    let word: String
    let translations: [String]

    var body: MessagesRequestBody {
        MessagesRequestBody(
            model: Self.model,
            maxTokens: Self.maxTokens,
            messages: [.init(role: "user", content: prompt)],
            outputConfig: .init(format: .init(type: "json_schema", schema: Self.schema))
        )
    }

    private var prompt: String {
        """
        Generate 2-3 simple example sentences for the English word "\(word)" \
        (Russian: \(translations.joined(separator: ", "))). \
        Requirements: each sentence is 5-8 common everyday English words; \
        each sentence contains the word "\(word)" exactly as written, \
        not an inflected form; sentences suit a beginner learning English. \
        For each sentence provide its natural Russian translation.
        """
    }

    private static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "sentences": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "en": .object(["type": .string("string")]),
                        "ru": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("en"), .string("ru")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ]),
        "required": .array([.string("sentences")]),
        "additionalProperties": .bool(false),
    ])
}
