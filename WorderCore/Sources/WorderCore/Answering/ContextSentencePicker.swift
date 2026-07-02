import Foundation

/// Picks a cached example sentence for the context exercise and masks the
/// studied word in it.
///
/// A sentence is usable when it contains the word as a whole word,
/// case-insensitively (exact form only — inflections like "shops" for "shop"
/// do not count, per the batch contract sentences use the word as-is). All
/// occurrences are masked, otherwise a repeated word would reveal the answer.
public struct ContextSentencePicker: Sendable {
    public static let mask = "____"

    public struct MaskedSentence: Equatable, Sendable {
        public let masked: String
        public let translation: String

        public init(masked: String, translation: String) {
            self.masked = masked
            self.translation = translation
        }
    }

    public init() {}

    public func hasUsableSentence(wordText: String, sentences: [WordBatchFile.Sentence]) -> Bool {
        guard let regex = wordRegex(for: wordText) else { return false }
        return sentences.contains { matches(regex, in: $0.en) }
    }

    public func pick(
        wordText: String,
        sentences: [WordBatchFile.Sentence],
        using rng: inout some RandomNumberGenerator
    ) -> MaskedSentence? {
        guard let regex = wordRegex(for: wordText) else { return nil }
        let usable = sentences.filter { matches(regex, in: $0.en) }
        guard let sentence = usable.randomElement(using: &rng) else { return nil }
        let masked = regex.stringByReplacingMatches(
            in: sentence.en,
            range: NSRange(sentence.en.startIndex..., in: sentence.en),
            withTemplate: Self.mask
        )
        return MaskedSentence(masked: masked, translation: sentence.ru)
    }

    private func wordRegex(for wordText: String) -> NSRegularExpression? {
        let trimmed = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trimmed))\\b"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
