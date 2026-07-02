import Foundation
import SwiftData

/// One unit of work in a study session.
public struct SessionItem: Equatable {
    public enum Kind: Equatable, Sendable {
        case introduction
        case exercise(Direction)
    }

    public let word: Word
    public let kind: Kind

    public init(word: Word, kind: Kind) {
        self.word = word
        self.kind = kind
    }

    public static func == (lhs: SessionItem, rhs: SessionItem) -> Bool {
        lhs.word === rhs.word && lhs.kind == rhs.kind
    }
}

/// Builds and drives the work queue of one study session.
///
/// Priority: overdue reviews (by due date), then introductions of new words up
/// to the daily limit. Completing an introduction inserts exercises for both
/// directions right after it. A failed exercise re-enters the same session
/// after an intra-session delay (default 1m, then 10m) until answered
/// correctly. The queue only orders work — persisting answers and scheduling
/// is the caller's job.
public final class SessionQueue {
    public struct Configuration: Equatable, Sendable {
        public var dailyNewWordLimit: Int
        public var intraSessionSteps: [TimeInterval]

        public init(dailyNewWordLimit: Int = 20, intraSessionSteps: [TimeInterval] = [60, 600]) {
            precondition(dailyNewWordLimit >= 0, "dailyNewWordLimit must be non-negative")
            precondition(!intraSessionSteps.isEmpty, "intraSessionSteps must not be empty")
            precondition(intraSessionSteps.allSatisfy { $0 > 0 }, "intraSessionSteps must be positive")
            self.dailyNewWordLimit = dailyNewWordLimit
            self.intraSessionSteps = intraSessionSteps
        }
    }

    private struct PendingItem {
        let item: SessionItem
        var notBefore: Date
        var failures: Int
    }

    private let configuration: Configuration
    private var pending: [PendingItem]

    /// New words planned for this session (introductions not yet completed).
    public private(set) var plannedNewWords: [Word]

    public init(
        context: ModelContext,
        configuration: Configuration = Configuration(),
        calendar: Calendar = Calendar.current,
        now: Date
    ) throws {
        self.configuration = configuration

        let newRaw = CardState.new.rawValue
        let dueStates = try context.fetch(FetchDescriptor<DirectionState>(
            predicate: #Predicate { $0.stateRaw != newRaw && $0.due <= now }
        ))
        let newStates = try context.fetch(FetchDescriptor<DirectionState>(
            predicate: #Predicate { $0.stateRaw == newRaw }
        ))

        var reviews: [(due: Date, item: SessionItem)] = dueStates.compactMap { state in
            guard let word = state.word else { return nil }
            return (state.due, SessionItem(word: word, kind: .exercise(state.direction)))
        }
        // Directions still `new` on words that were already introduced resume
        // as regular exercises — they must not wait for the new-word budget.
        for state in newStates {
            guard let word = state.word, state.due <= now else { continue }
            if word.directionStates.contains(where: { $0.state != .new }) {
                reviews.append((state.due, SessionItem(word: word, kind: .exercise(state.direction))))
            }
        }
        reviews.sort {
            ($0.due, $0.item.word.wordId, sortRank($0.item.kind))
                < ($1.due, $1.item.word.wordId, sortRank($1.item.kind))
        }

        var newWords: [Word] = []
        var seenWords = Set<PersistentIdentifier>()
        for state in newStates {
            guard let word = state.word, seenWords.insert(word.persistentModelID).inserted else { continue }
            if word.directionStates.allSatisfy({ $0.state == .new }) {
                newWords.append(word)
            }
        }
        newWords.sort {
            ($0.batch?.importedAt ?? .distantPast, $0.wordId)
                < ($1.batch?.importedAt ?? .distantPast, $1.wordId)
        }
        let introducedToday = try Self.wordsIntroducedCount(
            context: context,
            since: calendar.startOfDay(for: now)
        )
        let allowance = max(0, configuration.dailyNewWordLimit - introducedToday)
        self.plannedNewWords = Array(newWords.prefix(allowance))

        self.pending = reviews.map { PendingItem(item: $0.item, notBefore: .distantPast, failures: 0) }
            + plannedNewWords.map {
                PendingItem(item: SessionItem(word: $0, kind: .introduction), notBefore: .distantPast, failures: 0)
            }
    }

    public var isEmpty: Bool { pending.isEmpty }

    /// Items still queued. Grows when an introduction expands into exercises.
    public var remainingCount: Int { pending.count }

    /// The next item to work on. Items delayed by an intra-session step are
    /// skipped while others are ready; when only delayed items remain, the
    /// earliest one is served ahead of schedule rather than stalling.
    public func nextItem(now: Date) -> SessionItem? {
        if let ready = pending.first(where: { $0.notBefore <= now }) {
            return ready.item
        }
        return pending.min { $0.notBefore < $1.notBefore }?.item
    }

    /// Marks an introduction as shown or an exercise as answered correctly.
    /// A completed introduction inserts exercises for both directions in its place.
    public func markCompleted(_ item: SessionItem, now: Date) {
        guard let index = pending.firstIndex(where: { $0.item == item }) else {
            preconditionFailure("markCompleted for an item that is not in the queue")
        }
        pending.remove(at: index)
        if item.kind == .introduction {
            plannedNewWords.removeAll { $0 === item.word }
            let exercises = [Direction.enToRu, .ruToEn].map {
                PendingItem(
                    item: SessionItem(word: item.word, kind: .exercise($0)),
                    notBefore: .distantPast,
                    failures: 0
                )
            }
            pending.insert(contentsOf: exercises, at: index)
        }
    }

    /// Marks an exercise as answered incorrectly: the item re-enters the queue
    /// after the next intra-session step and must eventually be completed.
    public func markFailed(_ item: SessionItem, now: Date) {
        precondition(item.kind != .introduction, "an introduction cannot fail")
        guard let index = pending.firstIndex(where: { $0.item == item }) else {
            preconditionFailure("markFailed for an item that is not in the queue")
        }
        var failed = pending.remove(at: index)
        failed.failures += 1
        let stepIndex = min(failed.failures - 1, configuration.intraSessionSteps.count - 1)
        failed.notBefore = now.addingTimeInterval(configuration.intraSessionSteps[stepIndex])
        pending.append(failed)
    }

    /// A word counts as introduced once its first answer is logged. An
    /// introduction card alone leaves no trace, so an abandoned session does
    /// not consume the daily budget.
    private static func wordsIntroducedCount(context: ModelContext, since startOfDay: Date) throws -> Int {
        let todayLogs = try context.fetch(FetchDescriptor<ReviewLog>(
            predicate: #Predicate { $0.reviewedAt >= startOfDay }
        ))
        var counted = Set<PersistentIdentifier>()
        for log in todayLogs {
            guard let word = log.word, !counted.contains(word.persistentModelID) else { continue }
            if let earliest = word.reviewLogs.map(\.reviewedAt).min(), earliest >= startOfDay {
                counted.insert(word.persistentModelID)
            }
        }
        return counted.count
    }
}

private func sortRank(_ kind: SessionItem.Kind) -> Int {
    switch kind {
    case .introduction: 0
    case .exercise(let direction): direction == .enToRu ? 1 : 2
    }
}
