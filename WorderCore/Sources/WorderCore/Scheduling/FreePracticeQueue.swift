import Foundation
import SwiftData

/// Work queue for free practice: one weighted-shuffled round over the whole
/// dictionary, both directions of every word, an introduction card for words
/// never introduced before. Weak words (leeches, recent failures, low
/// stability) surface earlier and recently failed ones get a second pass;
/// well-learned words sink toward the tail. Purely a trainer — completing
/// items here must not move the FSRS schedule (the session engine enforces
/// that part).
public final class FreePracticeQueue: SessionWorkQueue {
    public struct Configuration: Equatable, Sendable {
        public var intraSessionSteps: [TimeInterval]
        public var sameWordSpacing: Int
        /// An `again` answer within this window (scheduled or free) marks the
        /// word as weak: it weighs more and earns a second exercise pass.
        public var recentFailureWindowDays: Double

        public init(
            intraSessionSteps: [TimeInterval] = [60, 600],
            sameWordSpacing: Int = 3,
            recentFailureWindowDays: Double = 14
        ) {
            precondition(!intraSessionSteps.isEmpty, "intraSessionSteps must not be empty")
            precondition(intraSessionSteps.allSatisfy { $0 > 0 }, "intraSessionSteps must be positive")
            precondition(sameWordSpacing >= 0, "sameWordSpacing must be non-negative")
            precondition(recentFailureWindowDays >= 0, "recentFailureWindowDays must be non-negative")
            self.intraSessionSteps = intraSessionSteps
            self.sameWordSpacing = sameWordSpacing
            self.recentFailureWindowDays = recentFailureWindowDays
        }
    }

    private struct PendingItem {
        let item: SessionItem
        var notBefore: Date
        var failures: Int
    }

    private let configuration: Configuration
    private var pending: [PendingItem]

    public init(
        context: ModelContext,
        configuration: Configuration = Configuration(),
        now: Date,
        using rng: inout some RandomNumberGenerator
    ) throws {
        self.configuration = configuration

        let words = try context.fetch(FetchDescriptor<Word>())
        var weighted: [(items: [SessionItem], weight: Double)] = []
        weighted.reserveCapacity(words.count)
        for word in words {
            let untouched = word.directionStates.allSatisfy { $0.state == .new }
                && word.reviewLogs.isEmpty
            let exercises = Direction.allCases.map { SessionItem(word: word, kind: .exercise($0)) }
            let weight = Self.weight(of: word, now: now, configuration: configuration)
            if untouched {
                weighted.append(([SessionItem(word: word, kind: .introduction)], weight))
            } else {
                weighted.append((exercises, weight))
                if Self.hasRecentFailure(word, now: now, configuration: configuration) {
                    // A second pass later in the round: repetition is the
                    // whole point for words that keep slipping.
                    weighted.append((exercises, weight / 2))
                }
            }
        }

        // Efraimidis–Spirakis weighted shuffle: key = U^(1/w), descending.
        // Same-word groups keep one key so their items travel together until
        // the spacing pass spreads them out.
        let ordered = weighted
            .map { group in
                (group.items, pow(Double.random(in: .ulpOfOne..<1, using: &rng), 1 / group.weight))
            }
            .sorted { $0.1 > $1.1 }
            .flatMap { $0.0 }

        self.pending = SessionQueue
            .spacingSameWords(ordered, minGap: configuration.sameWordSpacing)
            .map { PendingItem(item: $0, notBefore: .distantPast, failures: 0) }
    }

    /// Priority weight: leeches, fresh failures and fragile (low-stability)
    /// words float up; words solid in both directions sink.
    static func weight(of word: Word, now: Date, configuration: Configuration) -> Double {
        var weight = 1.0
        if word.isLeech {
            weight += 2
        }
        let cutoff = now.addingTimeInterval(-configuration.recentFailureWindowDays * 86_400)
        let recentFailures = word.reviewLogs
            .count { $0.grade == .again && $0.reviewedAt >= cutoff }
        weight += min(3, Double(recentFailures))

        let started = word.directionStates.filter { $0.state != .new }
        if !started.isEmpty {
            let minStability = started.map(\.stability).min() ?? 0
            if minStability < 7 {
                weight += 1.5
            }
            let solidBothWays = started.count == Direction.allCases.count
                && started.allSatisfy { $0.state == .review && $0.stability >= 21 }
            if solidBothWays && recentFailures == 0 {
                weight *= 0.5
            }
        }
        return weight
    }

    static func hasRecentFailure(_ word: Word, now: Date, configuration: Configuration) -> Bool {
        let cutoff = now.addingTimeInterval(-configuration.recentFailureWindowDays * 86_400)
        return word.reviewLogs.contains { $0.grade == .again && $0.reviewedAt >= cutoff }
    }

    public var isEmpty: Bool { pending.isEmpty }

    public var remainingCount: Int { pending.count }

    public func nextItem(now: Date) -> SessionItem? {
        if let ready = pending.first(where: { $0.notBefore <= now }) {
            return ready.item
        }
        return pending.min { $0.notBefore < $1.notBefore }?.item
    }

    public func markCompleted(_ item: SessionItem, now: Date) {
        guard let index = pending.firstIndex(where: { $0.item == item }) else {
            preconditionFailure("markCompleted for an item that is not in the queue")
        }
        pending.remove(at: index)
        if item.kind == .introduction {
            let gap = configuration.sameWordSpacing
            for (offset, direction) in [Direction.enToRu, .ruToEn].enumerated() {
                let target = min(index + gap * (offset + 1) + offset, pending.count)
                pending.insert(
                    PendingItem(
                        item: SessionItem(word: item.word, kind: .exercise(direction)),
                        notBefore: .distantPast,
                        failures: 0
                    ),
                    at: target
                )
            }
        }
    }

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
}
