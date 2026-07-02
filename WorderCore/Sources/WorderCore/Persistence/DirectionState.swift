import Foundation
import SwiftData

/// FSRS card state of one word in one translation direction.
/// Enum-backed fields are stored as raw strings so they stay usable in `#Predicate` queries.
@Model
public final class DirectionState {
    public var directionRaw: String
    public var stateRaw: String
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var lapses: Int
    public var reps: Int
    public var lastReviewedAt: Date?

    public var word: Word?

    public init(
        direction: Direction,
        state: CardState = .new,
        stability: Double = 0,
        difficulty: Double = 0,
        due: Date,
        lapses: Int = 0,
        reps: Int = 0,
        lastReviewedAt: Date? = nil
    ) {
        self.directionRaw = direction.rawValue
        self.stateRaw = state.rawValue
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lapses = lapses
        self.reps = reps
        self.lastReviewedAt = lastReviewedAt
    }

    public var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .enToRu }
        set { directionRaw = newValue.rawValue }
    }

    public var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }
}
