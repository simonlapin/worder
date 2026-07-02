import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let day: TimeInterval = 86_400

@Suite struct StatsCalculatorTests {
    private let calculator = StatsCalculator(calendar: Calendar(identifier: .gregorian))

    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    @discardableResult
    private func insertBatch(_ context: ModelContext, id: String, title: String, importedAt: Date) -> Batch {
        let batch = Batch(batchId: id, title: title, schemaVersion: 1, importedAt: importedAt)
        context.insert(batch)
        return batch
    }

    @discardableResult
    private func insertWord(
        _ context: ModelContext,
        id: Int,
        text: String,
        batch: Batch?,
        category: String? = nil,
        isLeech: Bool = false,
        leechHint: String? = nil
    ) -> Word {
        let word = Word(
            wordId: id,
            text: text,
            translations: ["перевод"],
            category: category,
            isLeech: isLeech,
            leechHint: leechHint
        )
        context.insert(word)
        word.batch = batch
        for direction in Direction.allCases {
            let state = DirectionState(direction: direction, due: now)
            context.insert(state)
            state.word = word
        }
        return word
    }

    private func promoteToLearned(_ word: Word) {
        for state in word.directionStates {
            state.state = .review
            state.lastReviewedAt = now.addingTimeInterval(-day)
            state.due = now.addingTimeInterval(29 * day)
            state.reps = 5
        }
    }

    private func startLearning(_ word: Word) {
        guard let state = word.directionState(for: .enToRu) else { return }
        state.state = .learning
        state.lastReviewedAt = now
        state.reps = 1
    }

    @discardableResult
    private func insertSession(
        _ context: ModelContext,
        daysAgo: Int,
        finished: Bool = true,
        answersTotal: Int = 10,
        answersCorrect: Int = 8,
        newWordsIntroduced: Int = 2
    ) -> StudySession {
        let start = now.addingTimeInterval(-Double(daysAgo) * day)
        let session = StudySession(
            startedAt: start,
            endedAt: finished ? start.addingTimeInterval(600) : nil,
            answersTotal: answersTotal,
            answersCorrect: answersCorrect,
            newWordsIntroduced: newWordsIntroduced
        )
        context.insert(session)
        return session
    }

    @Test func emptyDatabaseProducesEmptySnapshot() throws {
        let context = try makeContext()
        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot == StatsSnapshot())
    }

    @Test func totalsSplitWordsByMasteryStatus() throws {
        let context = try makeContext()
        let batch = insertBatch(context, id: "b1", title: "Batch 1", importedAt: now)
        insertWord(context, id: 1, text: "apple", batch: batch)
        startLearning(insertWord(context, id: 2, text: "pear", batch: batch))
        promoteToLearned(insertWord(context, id: 3, text: "plum", batch: batch))
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.totals == .init(new: 1, learning: 1, learned: 1))
        #expect(snapshot.totals.total == 3)
    }

    @Test func batchBreakdownFollowsImportOrderAndSeparatesCounts() throws {
        let context = try makeContext()
        let older = insertBatch(context, id: "core", title: "Core", importedAt: now.addingTimeInterval(-day))
        let newer = insertBatch(context, id: "extra", title: "Extra", importedAt: now)
        insertWord(context, id: 1, text: "apple", batch: older)
        promoteToLearned(insertWord(context, id: 2, text: "plum", batch: older))
        insertWord(context, id: 1, text: "quark", batch: newer)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.batches == [
            .init(title: "Core", counts: .init(new: 1, learned: 1)),
            .init(title: "Extra", counts: .init(new: 1)),
        ])
    }

    @Test func wordWithoutBatchCountsInTotalsOnly() throws {
        let context = try makeContext()
        let batch = insertBatch(context, id: "b1", title: "Batch 1", importedAt: now)
        insertWord(context, id: 1, text: "apple", batch: batch)
        insertWord(context, id: 99, text: "orphan", batch: nil)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.totals.total == 2)
        #expect(snapshot.batches == [.init(title: "Batch 1", counts: .init(new: 1))])
    }

    @Test func categoriesAggregateAcrossBatchesAndSkipUncategorized() throws {
        let context = try makeContext()
        let first = insertBatch(context, id: "b1", title: "Batch 1", importedAt: now.addingTimeInterval(-day))
        let second = insertBatch(context, id: "b2", title: "Batch 2", importedAt: now)
        insertWord(context, id: 1, text: "apple", batch: first, category: "food")
        insertWord(context, id: 2, text: "pear", batch: second, category: "food")
        insertWord(context, id: 3, text: "car", batch: first, category: "transport")
        insertWord(context, id: 4, text: "misc", batch: first)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.categories == [
            .init(title: "food", counts: .init(new: 2)),
            .init(title: "transport", counts: .init(new: 1)),
        ])
    }

    @Test func sessionHistoryIsFinishedOnlyNewestFirstAndCapped() throws {
        let context = try makeContext()
        for daysAgo in 1...5 {
            insertSession(context, daysAgo: daysAgo, answersTotal: daysAgo * 10)
        }
        insertSession(context, daysAgo: 0, finished: false)
        try context.save()

        let capped = StatsCalculator(
            configuration: .init(sessionHistoryLimit: 3),
            calendar: Calendar(identifier: .gregorian)
        )
        let snapshot = try capped.snapshot(in: context, now: now)

        #expect(snapshot.recentSessions.count == 3)
        #expect(snapshot.finishedSessionCount == 5)
        #expect(snapshot.recentSessions.map(\.answersTotal) == [10, 20, 30])
    }

    @Test func sessionAccuracyIsFractionAndNilWithoutAnswers() throws {
        let context = try makeContext()
        insertSession(context, daysAgo: 1, answersTotal: 8, answersCorrect: 6)
        insertSession(context, daysAgo: 2, answersTotal: 0, answersCorrect: 0)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.recentSessions[0].accuracy == 0.75)
        #expect(snapshot.recentSessions[1].accuracy == nil)
    }

    @Test func leechesAreListedAlphabeticallyWithHints() throws {
        let context = try makeContext()
        let batch = insertBatch(context, id: "b1", title: "Batch 1", importedAt: now)
        insertWord(context, id: 1, text: "store", batch: batch, isLeech: true)
        insertWord(context, id: 2, text: "shop", batch: batch, isLeech: true, leechHint: "shop is smaller")
        insertWord(context, id: 3, text: "plane", batch: batch)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        #expect(snapshot.leeches == [
            .init(text: "shop", translations: ["перевод"], hint: "shop is smaller"),
            .init(text: "store", translations: ["перевод"]),
        ])
    }

    @Test func streakMatchesStreakCalculator() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        insertSession(context, daysAgo: 0)
        insertSession(context, daysAgo: 1)
        insertSession(context, daysAgo: 3)
        try context.save()

        let snapshot = try calculator.snapshot(in: context, now: now)
        let expected = try StreakCalculator(calendar: calendar).currentStreak(in: context, now: now)
        #expect(snapshot.streakDays == expected)
        #expect(snapshot.streakDays == 2)
    }
}
