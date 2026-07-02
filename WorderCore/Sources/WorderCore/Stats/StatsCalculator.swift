import Foundation
import SwiftData

/// Immutable snapshot of learning progress for the stats screen.
public struct StatsSnapshot: Equatable, Sendable {
    public struct StatusCounts: Equatable, Sendable {
        public var new: Int
        public var learning: Int
        public var learned: Int

        public var total: Int { new + learning + learned }

        public init(new: Int = 0, learning: Int = 0, learned: Int = 0) {
            self.new = new
            self.learning = learning
            self.learned = learned
        }
    }

    public struct GroupBreakdown: Equatable, Sendable {
        public var title: String
        public var counts: StatusCounts

        public init(title: String, counts: StatusCounts) {
            self.title = title
            self.counts = counts
        }
    }

    public struct SessionRecord: Equatable, Sendable {
        public var startedAt: Date
        public var endedAt: Date
        public var answersTotal: Int
        public var answersCorrect: Int
        public var newWordsIntroduced: Int
        public var mode: StudySessionMode

        /// Fraction 0...1; nil when the session recorded no answers.
        public var accuracy: Double? {
            answersTotal > 0 ? Double(answersCorrect) / Double(answersTotal) : nil
        }

        public init(
            startedAt: Date,
            endedAt: Date,
            answersTotal: Int,
            answersCorrect: Int,
            newWordsIntroduced: Int,
            mode: StudySessionMode = .scheduled
        ) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.answersTotal = answersTotal
            self.answersCorrect = answersCorrect
            self.newWordsIntroduced = newWordsIntroduced
            self.mode = mode
        }
    }

    public struct LeechRecord: Equatable, Sendable {
        public var text: String
        public var translations: [String]
        public var hint: String?

        public init(text: String, translations: [String], hint: String? = nil) {
            self.text = text
            self.translations = translations
            self.hint = hint
        }
    }

    public var totals: StatusCounts
    /// Per-batch breakdown in import order.
    public var batches: [GroupBreakdown]
    /// Per-category breakdown (words without a category are excluded); empty
    /// when no word has a category.
    public var categories: [GroupBreakdown]
    /// Finished sessions, newest first, capped by `sessionHistoryLimit`.
    public var recentSessions: [SessionRecord]
    /// Total finished sessions, including those beyond the history cap.
    public var finishedSessionCount: Int
    /// Words currently flagged as leeches, alphabetical.
    public var leeches: [LeechRecord]
    public var streakDays: Int

    public init(
        totals: StatusCounts = StatusCounts(),
        batches: [GroupBreakdown] = [],
        categories: [GroupBreakdown] = [],
        recentSessions: [SessionRecord] = [],
        finishedSessionCount: Int = 0,
        leeches: [LeechRecord] = [],
        streakDays: Int = 0
    ) {
        self.totals = totals
        self.batches = batches
        self.categories = categories
        self.recentSessions = recentSessions
        self.finishedSessionCount = finishedSessionCount
        self.leeches = leeches
        self.streakDays = streakDays
    }
}

/// Builds a `StatsSnapshot` from the database. Word statuses come from
/// `MasteryPolicy`, the streak from `StreakCalculator` — the stats screen
/// shows the same numbers the scheduler acts on.
public struct StatsCalculator: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var sessionHistoryLimit: Int

        public init(sessionHistoryLimit: Int = 30) {
            precondition(sessionHistoryLimit >= 0, "sessionHistoryLimit must be non-negative")
            self.sessionHistoryLimit = sessionHistoryLimit
        }
    }

    private let configuration: Configuration
    private let masteryPolicy: MasteryPolicy
    private let calendar: Calendar

    public init(
        configuration: Configuration = Configuration(),
        masteryPolicy: MasteryPolicy = MasteryPolicy(),
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.masteryPolicy = masteryPolicy
        self.calendar = calendar
    }

    public func snapshot(in context: ModelContext, now: Date) throws -> StatsSnapshot {
        let batches = try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.importedAt), SortDescriptor(\.batchId)]
        ))
        let words = try context.fetch(FetchDescriptor<Word>())

        var totals = StatsSnapshot.StatusCounts()
        var batchCounts: [PersistentIdentifier: StatsSnapshot.StatusCounts] = [:]
        var categoryCounts: [String: StatsSnapshot.StatusCounts] = [:]
        var leeches: [StatsSnapshot.LeechRecord] = []

        for word in words {
            let status = masteryPolicy.status(of: word, now: now)
            totals.add(status)
            if let batch = word.batch {
                batchCounts[batch.persistentModelID, default: StatsSnapshot.StatusCounts()].add(status)
            }
            if let category = word.category {
                categoryCounts[category, default: StatsSnapshot.StatusCounts()].add(status)
            }
            if word.isLeech {
                leeches.append(StatsSnapshot.LeechRecord(
                    text: word.text,
                    translations: word.translations,
                    hint: word.leechHint
                ))
            }
        }

        let batchBreakdowns = batches.map { batch in
            StatsSnapshot.GroupBreakdown(
                title: batch.title,
                counts: batchCounts[batch.persistentModelID] ?? StatsSnapshot.StatusCounts()
            )
        }

        let categories = categoryCounts
            .sorted { $0.key < $1.key }
            .map { StatsSnapshot.GroupBreakdown(title: $0.key, counts: $0.value) }

        let finished = try context.fetch(FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        let recentSessions = finished.prefix(configuration.sessionHistoryLimit).compactMap { session in
            session.endedAt.map { endedAt in
                StatsSnapshot.SessionRecord(
                    startedAt: session.startedAt,
                    endedAt: endedAt,
                    answersTotal: session.answersTotal,
                    answersCorrect: session.answersCorrect,
                    newWordsIntroduced: session.newWordsIntroduced,
                    mode: session.mode
                )
            }
        }

        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: finished.map(\.startedAt), now: now)

        return StatsSnapshot(
            totals: totals,
            batches: batchBreakdowns,
            categories: categories,
            recentSessions: recentSessions,
            finishedSessionCount: finished.count,
            leeches: leeches.sorted { $0.text < $1.text },
            streakDays: streak
        )
    }
}

private extension StatsSnapshot.StatusCounts {
    mutating func add(_ status: WordStatus) {
        switch status {
        case .new: new += 1
        case .learning: learning += 1
        case .learned: learned += 1
        }
    }
}
