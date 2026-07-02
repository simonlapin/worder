import Foundation

public enum ExerciseType: String, Codable, Sendable, CaseIterable {
    case multipleChoice
    case typedAnswer
    case listening
    case context
}

/// Chooses an exercise type matching the maturity of one direction's card.
///
/// Ladder: multiple choice while the card is young or (re)learning; typed
/// answer for RU→EN once the memory is established; on mature cards listening
/// (EN→RU, needs audio) and context (RU→EN, needs cached sentences) join the
/// rotation. Randomness comes from an injected generator for determinism.
public struct ExerciseSelector: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Stability (days) from which RU→EN switches to typed answers.
        public var typedAnswerStability: Double
        /// Stability (days) from which listening/context join the rotation.
        public var matureStability: Double

        public init(typedAnswerStability: Double = 3, matureStability: Double = 21) {
            precondition(typedAnswerStability > 0, "typedAnswerStability must be positive")
            precondition(
                matureStability >= typedAnswerStability,
                "matureStability must not be below typedAnswerStability"
            )
            self.typedAnswerStability = typedAnswerStability
            self.matureStability = matureStability
        }
    }

    /// What the app can offer right now for a specific word.
    public struct Capabilities: Equatable, Sendable {
        /// The word has cached example sentences (enables the context exercise).
        public var hasCachedSentences: Bool
        /// A speech voice is available (enables the listening exercise).
        public var canPlayAudio: Bool

        public init(hasCachedSentences: Bool = false, canPlayAudio: Bool = false) {
            self.hasCachedSentences = hasCachedSentences
            self.canPlayAudio = canPlayAudio
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func exerciseType(
        for card: SchedulerCard,
        direction: Direction,
        capabilities: Capabilities,
        using rng: inout some RandomNumberGenerator
    ) -> ExerciseType {
        guard card.state == .review else { return .multipleChoice }

        let base: ExerciseType = switch direction {
        case .enToRu:
            .multipleChoice
        case .ruToEn:
            card.stability >= configuration.typedAnswerStability ? .typedAnswer : .multipleChoice
        }
        guard card.stability >= configuration.matureStability else { return base }

        var pool = [base]
        switch direction {
        case .enToRu where capabilities.canPlayAudio:
            pool.append(.listening)
        case .ruToEn where capabilities.hasCachedSentences:
            pool.append(.context)
        default:
            break
        }
        return pool.randomElement(using: &rng) ?? base
    }
}
