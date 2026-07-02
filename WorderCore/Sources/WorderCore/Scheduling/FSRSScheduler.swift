import FSRS
import Foundation

/// FSRS-6 implementation of `Scheduler` (open-spaced-repetition/swift-fsrs).
///
/// Runs the long-term scheduler (`enableShortTerm: false`): FSRS owns
/// day-level intervals only, while intra-session repetition of failed words
/// is the session queue's job. Fuzz is disabled for determinism.
///
/// The library also declares `CardState`/`ReviewLog`, colliding with our
/// domain types — mappings below rely on contextual inference instead of
/// qualified names (the `FSRS` module and its `FSRS` class shadow each other).
public struct FSRSScheduler: Scheduler {
    private let fsrs: FSRS

    public init(desiredRetention: Double = 0.9) {
        let parameters = FSRSParameters(
            requestRetention: desiredRetention,
            w: FSRSDefaults.defaultWv6,
            enableFuzz: false,
            enableShortTerm: false
        )
        self.fsrs = FSRS(parameters: parameters)
    }

    public func next(card: SchedulerCard, grade: ReviewGrade, now: Date) throws -> SchedulerCard {
        let result = try fsrs.next(card: libraryCard(from: card), now: now, grade: rating(from: grade))
        return snapshot(from: result.card)
    }

    private func libraryCard(from card: SchedulerCard) -> Card {
        var library = Card(
            due: card.due,
            stability: card.stability,
            difficulty: card.difficulty,
            reps: card.reps,
            lapses: card.lapses,
            lastReview: card.lastReviewedAt
        )
        switch card.state {
        case .new: library.state = .new
        case .learning: library.state = .learning
        case .review: library.state = .review
        case .relearning: library.state = .relearning
        }
        return library
    }

    private func snapshot(from library: Card) -> SchedulerCard {
        let state: CardState = switch library.state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
        return SchedulerCard(
            state: state,
            stability: library.stability,
            difficulty: library.difficulty,
            due: library.due,
            lapses: library.lapses,
            reps: library.reps,
            lastReviewedAt: library.lastReview
        )
    }

    private func rating(from grade: ReviewGrade) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}
