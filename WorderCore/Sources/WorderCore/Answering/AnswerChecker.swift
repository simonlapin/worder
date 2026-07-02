import Foundation

/// Outcome of checking a typed answer, from full credit down to failure.
public enum AnswerVerdict: Equatable, Sendable {
    case correct
    /// A different dictionary word sharing the prompted translation
    /// (e.g. "store" when "shop" was asked). Counts as correct; `intended`
    /// lets the UI show which word the exercise was actually about.
    case correctSynonym(intended: String)
    /// A single-character slip of a correct answer. Accepted, but graded
    /// `.hard` so the scheduler shortens the next interval.
    case almostCorrect
    case wrong

    public var reviewGrade: ReviewGrade {
        switch self {
        case .correct, .correctSynonym: .good
        case .almostCorrect: .hard
        case .wrong: .again
        }
    }
}

/// Grades typed answers in both directions.
///
/// EN→RU accepts any of the word's own translations. RU→EN accepts the asked
/// word or any dictionary word sharing one of its translations (synonyms,
/// resolved through `TranslationIndex`). Single-edit typos of an accepted
/// answer (Damerau-Levenshtein distance 1) count as `almostCorrect`, but only
/// when the intended answer is long enough for a slip to be distinguishable
/// from a different short word.
public struct AnswerChecker: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Minimum length of the intended answer for typo tolerance to apply.
        public var typoMinimumLength: Int

        public init(typoMinimumLength: Int = 4) {
            precondition(typoMinimumLength > 0, "typoMinimumLength must be positive")
            self.typoMinimumLength = typoMinimumLength
        }
    }

    private let index: TranslationIndex
    private let configuration: Configuration

    public init(index: TranslationIndex, configuration: Configuration = Configuration()) {
        self.index = index
        self.configuration = configuration
    }

    /// Checks `input` for the exercise on `wordText` with its `translations`.
    /// `direction` decides what the user was expected to type: a Russian
    /// translation for `.enToRu`, the English word for `.ruToEn`.
    public func check(
        _ input: String,
        direction: Direction,
        wordText: String,
        translations: [String]
    ) -> AnswerVerdict {
        let answer = TranslationIndex.normalize(input)
        guard !answer.isEmpty else { return .wrong }

        switch direction {
        case .enToRu:
            return checkTranslationAnswer(answer, translations: translations)
        case .ruToEn:
            return checkWordAnswer(answer, wordText: wordText, translations: translations)
        }
    }

    private func checkTranslationAnswer(_ answer: String, translations: [String]) -> AnswerVerdict {
        let accepted = translations.map(TranslationIndex.normalize)
        if accepted.contains(answer) { return .correct }
        if accepted.contains(where: { isTypo(answer, of: $0) }) { return .almostCorrect }
        return .wrong
    }

    private func checkWordAnswer(
        _ answer: String,
        wordText: String,
        translations: [String]
    ) -> AnswerVerdict {
        let expected = TranslationIndex.normalize(wordText)
        if answer == expected { return .correct }

        let synonyms = translations
            .reduce(into: Set<String>()) { $0.formUnion(index.englishWords(for: $1)) }
            .map(TranslationIndex.normalize)
            .filter { $0 != expected }
        if synonyms.contains(answer) { return .correctSynonym(intended: wordText) }

        if isTypo(answer, of: expected) { return .almostCorrect }
        if synonyms.contains(where: { isTypo(answer, of: $0) }) { return .almostCorrect }
        return .wrong
    }

    private func isTypo(_ answer: String, of intended: String) -> Bool {
        intended.count >= configuration.typoMinimumLength
            && DamerauLevenshtein.distance(answer, intended) == 1
    }
}
