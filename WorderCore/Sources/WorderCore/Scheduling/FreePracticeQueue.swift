import Foundation
import SwiftData

/// Work queue for free practice: one shuffled round over the whole
/// dictionary, both directions of every word, an introduction card for words
/// never introduced before. Purely a trainer — completing items here must
/// not move the FSRS schedule (the session engine enforces that part).
public final class FreePracticeQueue: SessionWorkQueue {
    public struct Configuration: Equatable, Sendable {
        public var intraSessionSteps: [TimeInterval]
        public var sameWordSpacing: Int

        public init(
            intraSessionSteps: [TimeInterval] = [60, 600],
            sameWordSpacing: Int = 3
        ) {
            precondition(!intraSessionSteps.isEmpty, "intraSessionSteps must not be empty")
            precondition(intraSessionSteps.allSatisfy { $0 > 0 }, "intraSessionSteps must be positive")
            precondition(sameWordSpacing >= 0, "sameWordSpacing must be non-negative")
            self.intraSessionSteps = intraSessionSteps
            self.sameWordSpacing = sameWordSpacing
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
        using rng: inout some RandomNumberGenerator
    ) throws {
        self.configuration = configuration

        let words = try context.fetch(FetchDescriptor<Word>())
        var items: [SessionItem] = []
        items.reserveCapacity(words.count * 2)
        for word in words {
            let untouched = word.directionStates.allSatisfy { $0.state == .new }
                && word.reviewLogs.isEmpty
            if untouched {
                items.append(SessionItem(word: word, kind: .introduction))
            } else {
                for direction in Direction.allCases {
                    items.append(SessionItem(word: word, kind: .exercise(direction)))
                }
            }
        }
        items.shuffle(using: &rng)
        self.pending = SessionQueue
            .spacingSameWords(items, minGap: configuration.sameWordSpacing)
            .map { PendingItem(item: $0, notBefore: .distantPast, failures: 0) }
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
