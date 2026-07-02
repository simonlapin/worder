import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let day: TimeInterval = 86_400
private let importDate = now.addingTimeInterval(-30 * day)

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func makeContext() throws -> ModelContext {
    ModelContext(try WorderModelContainer.make(inMemory: true))
}

/// Imports `count` words (wordId 1...count) and returns them ordered by wordId.
private func importWords(_ context: ModelContext, count: Int) throws -> [Word] {
    let entries = (1...count).map {
        WordBatchFile.Entry(id: $0, word: "word\($0)", translations: ["слово\($0)"])
    }
    try BatchImporter(context: context)
        .importBatch(WordBatchFile(batchId: "b", title: "t", words: entries), now: importDate)
    return try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
}

private func makeQueue(
    _ context: ModelContext,
    limit: Int = 20,
    steps: [TimeInterval] = [60, 600]
) throws -> SessionQueue {
    try SessionQueue(
        context: context,
        configuration: .init(dailyNewWordLimit: limit, intraSessionSteps: steps),
        calendar: utcCalendar,
        now: now
    )
}

private func promote(
    _ word: Word,
    direction: Direction,
    due: Date,
    reviewedAt: Date? = nil
) throws {
    let state = try #require(word.directionState(for: direction))
    state.state = .review
    state.due = due
    state.reps = 1
    state.lastReviewedAt = reviewedAt ?? importDate
}

@Suite struct SessionQueueCompositionTests {
    @Test func emptyDatabaseYieldsEmptyQueue() throws {
        let queue = try makeQueue(try makeContext())
        #expect(queue.isEmpty)
        #expect(queue.nextItem(now: now) == nil)
    }

    @Test func freshDatabaseYieldsIntroductionsUpToLimit() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 5)
        let queue = try makeQueue(context, limit: 3)

        #expect(queue.remainingCount == 3)
        #expect(queue.plannedNewWords.map(\.wordId) == [1, 2, 3])
        #expect(queue.nextItem(now: now) == SessionItem(word: words[0], kind: .introduction))
    }

    @Test func overdueReviewsComeBeforeIntroductionsOrderedByDue() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 3)
        try promote(words[1], direction: .ruToEn, due: now.addingTimeInterval(-5 * day))
        try promote(words[1], direction: .enToRu, due: now.addingTimeInterval(day))
        try promote(words[2], direction: .enToRu, due: now.addingTimeInterval(-2 * day))
        try promote(words[2], direction: .ruToEn, due: now.addingTimeInterval(day))
        try context.save()

        let queue = try makeQueue(context, limit: 20)

        let first = try #require(queue.nextItem(now: now))
        #expect(first == SessionItem(word: words[1], kind: .exercise(.ruToEn)))
        queue.markCompleted(first, now: now)
        let second = try #require(queue.nextItem(now: now))
        #expect(second == SessionItem(word: words[2], kind: .exercise(.enToRu)))
        queue.markCompleted(second, now: now)
        #expect(queue.nextItem(now: now) == SessionItem(word: words[0], kind: .introduction))
    }

    @Test func futureReviewsAreExcluded() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 1)
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(day))
        try promote(words[0], direction: .ruToEn, due: now.addingTimeInterval(2 * day))
        try context.save()

        let queue = try makeQueue(context)
        #expect(queue.isEmpty)
    }

    @Test func partiallyIntroducedWordResumesWithoutConsumingNewBudget() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 2)
        // word1: enToRu already in review (not due), ruToEn never exercised.
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(day))
        try context.save()

        let queue = try makeQueue(context, limit: 1)

        #expect(queue.plannedNewWords.map(\.wordId) == [2])
        let first = try #require(queue.nextItem(now: now))
        #expect(first == SessionItem(word: words[0], kind: .exercise(.ruToEn)))
    }
}

@Suite struct SessionQueueDailyLimitTests {
    private func logAnswer(_ context: ModelContext, word: Word, at date: Date) {
        let log = ReviewLog(reviewedAt: date, direction: .enToRu, grade: .good)
        context.insert(log)
        log.word = word
    }

    @Test func wordsIntroducedTodayReduceTheAllowance() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 5)
        let today = now.addingTimeInterval(-3_600)
        let yesterday = now.addingTimeInterval(-day)

        // word1 introduced today (first log today).
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(day), reviewedAt: today)
        try promote(words[0], direction: .ruToEn, due: now.addingTimeInterval(day), reviewedAt: today)
        logAnswer(context, word: words[0], at: today)
        // word2 introduced yesterday, also reviewed today — must not count.
        try promote(words[1], direction: .enToRu, due: now.addingTimeInterval(day), reviewedAt: today)
        try promote(words[1], direction: .ruToEn, due: now.addingTimeInterval(day), reviewedAt: today)
        logAnswer(context, word: words[1], at: yesterday)
        logAnswer(context, word: words[1], at: today)
        try context.save()

        let queue = try makeQueue(context, limit: 2)

        #expect(queue.plannedNewWords.map(\.wordId) == [3])
    }

    @Test func exhaustedAllowanceYieldsNoIntroductions() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 3)
        let today = now.addingTimeInterval(-3_600)
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(day), reviewedAt: today)
        try promote(words[0], direction: .ruToEn, due: now.addingTimeInterval(day), reviewedAt: today)
        logAnswer(context, word: words[0], at: today)
        try context.save()

        let queue = try makeQueue(context, limit: 1)
        #expect(queue.plannedNewWords.isEmpty)
        #expect(queue.isEmpty)
    }

    @Test func zeroLimitDisablesIntroductions() throws {
        let context = try makeContext()
        _ = try importWords(context, count: 3)
        let queue = try makeQueue(context, limit: 0)
        #expect(queue.isEmpty)
    }
}

@Suite struct SessionQueueFlowTests {
    @Test func completedIntroductionExpandsIntoBothDirections() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 1)
        let queue = try makeQueue(context, limit: 1)

        let intro = try #require(queue.nextItem(now: now))
        #expect(intro.kind == .introduction)
        queue.markCompleted(intro, now: now)

        #expect(queue.plannedNewWords.isEmpty)
        #expect(queue.remainingCount == 2)
        let first = try #require(queue.nextItem(now: now))
        #expect(first == SessionItem(word: words[0], kind: .exercise(.enToRu)))
        queue.markCompleted(first, now: now)
        let second = try #require(queue.nextItem(now: now))
        #expect(second == SessionItem(word: words[0], kind: .exercise(.ruToEn)))
        queue.markCompleted(second, now: now)
        #expect(queue.isEmpty)
    }

    @Test func failedExerciseIsDelayedWhileOthersAreReady() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 1)
        let queue = try makeQueue(context, limit: 1)
        queue.markCompleted(try #require(queue.nextItem(now: now)), now: now)

        let enToRu = SessionItem(word: words[0], kind: .exercise(.enToRu))
        queue.markFailed(enToRu, now: now)

        // Delayed by the 60s step — the other direction is served meanwhile.
        #expect(queue.nextItem(now: now) == SessionItem(word: words[0], kind: .exercise(.ruToEn)))
        // After the step elapses it is ready again (and first in line).
        #expect(queue.nextItem(now: now.addingTimeInterval(61)) == SessionItem(word: words[0], kind: .exercise(.ruToEn)))
        queue.markCompleted(SessionItem(word: words[0], kind: .exercise(.ruToEn)), now: now)
        #expect(queue.nextItem(now: now.addingTimeInterval(61)) == enToRu)
    }

    @Test func onlyDelayedItemsRemainingAreServedEarly() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 1)
        let queue = try makeQueue(context, limit: 1)
        queue.markCompleted(try #require(queue.nextItem(now: now)), now: now)
        queue.markCompleted(SessionItem(word: words[0], kind: .exercise(.ruToEn)), now: now)

        let enToRu = SessionItem(word: words[0], kind: .exercise(.enToRu))
        queue.markFailed(enToRu, now: now)

        // Nothing else is ready — the delayed item is served ahead of schedule.
        #expect(queue.remainingCount == 1)
        #expect(queue.nextItem(now: now) == enToRu)
        queue.markCompleted(enToRu, now: now)
        #expect(queue.isEmpty)
    }

    @Test func secondFailureUsesTheLongerStep() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 2)
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(-day))
        try promote(words[0], direction: .ruToEn, due: now.addingTimeInterval(day))
        try promote(words[1], direction: .enToRu, due: now.addingTimeInterval(-day))
        try promote(words[1], direction: .ruToEn, due: now.addingTimeInterval(day))
        try context.save()

        let queue = try makeQueue(context, limit: 0)
        let first = SessionItem(word: words[0], kind: .exercise(.enToRu))
        let second = SessionItem(word: words[1], kind: .exercise(.enToRu))

        queue.markFailed(first, now: now)                                // → now + 60
        let retryAt = now.addingTimeInterval(70)
        queue.markFailed(first, now: retryAt)                            // → retryAt + 600
        queue.markFailed(second, now: retryAt)                           // → retryAt + 60

        // 70s after the retries: `second` (60s step) is ready, `first` (600s step) is not.
        #expect(queue.nextItem(now: retryAt.addingTimeInterval(70)) == second)
    }

    @Test func failureBeyondConfiguredStepsKeepsTheLastStep() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 2)
        try promote(words[0], direction: .enToRu, due: now.addingTimeInterval(-day))
        try promote(words[0], direction: .ruToEn, due: now.addingTimeInterval(day))
        try promote(words[1], direction: .enToRu, due: now.addingTimeInterval(-day))
        try promote(words[1], direction: .ruToEn, due: now.addingTimeInterval(day))
        try context.save()

        let queue = try makeQueue(context, limit: 0, steps: [60])
        let first = SessionItem(word: words[0], kind: .exercise(.enToRu))
        let second = SessionItem(word: words[1], kind: .exercise(.enToRu))

        // The second failure has no second step configured — it reuses 60s.
        queue.markFailed(first, now: now)
        queue.markFailed(first, now: now)                        // → now + 60
        queue.markFailed(second, now: now.addingTimeInterval(30)) // → now + 90

        // 61s in: `first` (retried with the clamped 60s step) is ready, `second` is not.
        #expect(queue.nextItem(now: now.addingTimeInterval(61)) == first)
    }
}
