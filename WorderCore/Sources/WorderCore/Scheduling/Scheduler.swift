import Foundation

/// Value snapshot of one direction's spaced-repetition card, decoupled from
/// both SwiftData and the underlying FSRS library.
public struct SchedulerCard: Equatable, Sendable {
    public var state: CardState
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var lapses: Int
    public var reps: Int
    public var lastReviewedAt: Date?

    public init(
        state: CardState = .new,
        stability: Double = 0,
        difficulty: Double = 0,
        due: Date,
        lapses: Int = 0,
        reps: Int = 0,
        lastReviewedAt: Date? = nil
    ) {
        self.state = state
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lapses = lapses
        self.reps = reps
        self.lastReviewedAt = lastReviewedAt
    }
}

/// Spaced-repetition scheduling behind a protocol so the FSRS dependency
/// stays replaceable and session logic stays testable with fakes.
public protocol Scheduler: Sendable {
    /// Applies a graded review at `now` and returns the card's next state.
    func next(card: SchedulerCard, grade: ReviewGrade, now: Date) throws -> SchedulerCard
}

extension DirectionState {
    public var schedulerCard: SchedulerCard {
        SchedulerCard(
            state: state,
            stability: stability,
            difficulty: difficulty,
            due: due,
            lapses: lapses,
            reps: reps,
            lastReviewedAt: lastReviewedAt
        )
    }

    public func apply(_ card: SchedulerCard) {
        state = card.state
        stability = card.stability
        difficulty = card.difficulty
        due = card.due
        lapses = card.lapses
        reps = card.reps
        lastReviewedAt = card.lastReviewedAt
    }
}
