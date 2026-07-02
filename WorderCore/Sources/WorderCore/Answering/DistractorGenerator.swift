import Foundation

/// Value snapshot of a word considered as distractor material, decoupled
/// from SwiftData so generation stays a pure function.
public struct DistractorCandidate: Equatable, Sendable {
    public var text: String
    public var translations: [String]
    public var category: String?
    public var batchId: String?

    public init(
        text: String,
        translations: [String],
        category: String? = nil,
        batchId: String? = nil
    ) {
        self.text = text
        self.translations = translations
        self.category = category
        self.batchId = batchId
    }

    public init(word: Word) {
        self.init(
            text: word.text,
            translations: word.translations,
            category: word.category,
            batchId: word.batch?.batchId
        )
    }
}

/// Produces plausible but guaranteed-wrong options for multiple choice.
///
/// Candidates sharing ANY translation with the target are excluded outright —
/// otherwise a question could carry two correct options (shop/store both mean
/// «магазин»). Remaining candidates are ranked by affinity (same category,
/// same batch, closest option length) and sampled from the top of that
/// ranking with an injected generator for determinism.
public struct DistractorGenerator: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var count: Int
        /// Top-ranked candidates the result is sampled from; keeps options
        /// plausible while still varying between questions.
        public var samplingPoolSize: Int

        public init(count: Int = 3, samplingPoolSize: Int = 12) {
            precondition(count > 0, "count must be positive")
            precondition(samplingPoolSize >= count, "samplingPoolSize must not be below count")
            self.count = count
            self.samplingPoolSize = samplingPoolSize
        }
    }

    public enum GenerationError: Error, Equatable {
        case insufficientCandidates(required: Int, available: Int)
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Returns exactly `configuration.count` distractor option strings for
    /// the exercise on `target`: English words for `.ruToEn`, Russian
    /// translations for `.enToRu`.
    public func distractors(
        for target: DistractorCandidate,
        direction: Direction,
        candidates: [DistractorCandidate],
        using rng: inout some RandomNumberGenerator
    ) throws -> [String] {
        let targetText = TranslationIndex.normalize(target.text)
        let targetTranslations = Set(target.translations.map(TranslationIndex.normalize))
        let referenceLength = switch direction {
        case .enToRu: target.translations.first?.count ?? 0
        case .ruToEn: target.text.count
        }

        let eligible: [(option: String, rank: (Int, Int, Int, String))] = candidates.compactMap { candidate in
            guard TranslationIndex.normalize(candidate.text) != targetText else { return nil }
            let candidateTranslations = Set(candidate.translations.map(TranslationIndex.normalize))
            guard targetTranslations.isDisjoint(with: candidateTranslations) else { return nil }

            let option: String? = switch direction {
            case .enToRu: candidate.translations.first
            case .ruToEn: candidate.text
            }
            guard let option, !TranslationIndex.normalize(option).isEmpty else { return nil }

            let rank = (
                candidate.category == target.category ? 0 : 1,
                candidate.batchId == target.batchId ? 0 : 1,
                abs(option.count - referenceLength),
                TranslationIndex.normalize(option)
            )
            return (option, rank)
        }

        var seenOptions: Set<String> = []
        let ranked = eligible
            .sorted { $0.rank < $1.rank }
            .filter { seenOptions.insert(TranslationIndex.normalize($0.option)).inserted }
            .map(\.option)

        guard ranked.count >= configuration.count else {
            throw GenerationError.insufficientCandidates(
                required: configuration.count,
                available: ranked.count
            )
        }
        return Array(
            ranked.prefix(configuration.samplingPoolSize)
                .shuffled(using: &rng)
                .prefix(configuration.count)
        )
    }
}
