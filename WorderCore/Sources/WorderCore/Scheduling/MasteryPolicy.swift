import Foundation

/// Word-level learning status derived from per-direction card states.
public enum WordStatus: String, Codable, Sendable, CaseIterable {
    case new
    case learning
    case learned
}

/// Decides when a word counts as learned: both directions must sit in review
/// with a scheduled interval at or above the threshold, with no lapse inside
/// the recent window. Learned words never leave the FSRS schedule — they keep
/// getting rare maintenance reviews, and a fresh lapse demotes them back to
/// learning.
public struct MasteryPolicy: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Scheduled interval (days) both directions must reach.
        public var minIntervalDays: Double
        /// An `again` answer within this many days blocks the learned status.
        public var recentLapseWindowDays: Double

        public init(minIntervalDays: Double = 21, recentLapseWindowDays: Double = 14) {
            precondition(minIntervalDays > 0, "minIntervalDays must be positive")
            precondition(recentLapseWindowDays >= 0, "recentLapseWindowDays must be non-negative")
            self.minIntervalDays = minIntervalDays
            self.recentLapseWindowDays = recentLapseWindowDays
        }
    }

    private static let secondsPerDay: TimeInterval = 86_400

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func status(of word: Word, now: Date) -> WordStatus {
        let states = word.directionStates
        if states.isEmpty || states.allSatisfy({ $0.state == .new }) {
            return .new
        }
        return isLearned(word, now: now) ? .learned : .learning
    }

    private func isLearned(_ word: Word, now: Date) -> Bool {
        let statesByDirection = Dictionary(
            word.directionStates.map { ($0.direction, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for direction in Direction.allCases {
            guard
                let state = statesByDirection[direction],
                state.state == .review,
                let lastReviewedAt = state.lastReviewedAt
            else { return false }
            let intervalDays = state.due.timeIntervalSince(lastReviewedAt) / Self.secondsPerDay
            guard intervalDays >= configuration.minIntervalDays else { return false }
        }

        let lapseCutoff = now.addingTimeInterval(-configuration.recentLapseWindowDays * Self.secondsPerDay)
        return !word.reviewLogs.contains { $0.grade == .again && $0.reviewedAt >= lapseCutoff }
    }
}
