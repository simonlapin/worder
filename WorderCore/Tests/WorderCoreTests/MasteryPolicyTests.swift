import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let day: TimeInterval = 86_400

@Suite struct MasteryPolicyTests {
    private let policy = MasteryPolicy()

    private func makeWord(_ context: ModelContext) -> Word {
        let word = Word(wordId: 1, text: "shop", translations: ["магазин"])
        context.insert(word)
        for direction in Direction.allCases {
            let state = DirectionState(direction: direction, due: now)
            context.insert(state)
            state.word = word
        }
        return word
    }

    private func promote(
        _ word: Word,
        _ direction: Direction,
        intervalDays: Double,
        state: CardState = .review
    ) throws {
        let directionState = try #require(word.directionState(for: direction))
        directionState.state = state
        directionState.lastReviewedAt = now.addingTimeInterval(-day)
        directionState.due = now.addingTimeInterval((intervalDays - 1) * day)
        directionState.reps = 5
    }

    private func logAgain(_ context: ModelContext, word: Word, at date: Date) {
        let log = ReviewLog(reviewedAt: date, direction: .enToRu, grade: .again)
        context.insert(log)
        log.word = word
    }

    @Test func untouchedWordIsNew() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        #expect(policy.status(of: word, now: now) == .new)
    }

    @Test func wordWithoutDirectionStatesIsNew() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = Word(wordId: 2, text: "store", translations: ["магазин"])
        context.insert(word)
        #expect(policy.status(of: word, now: now) == .new)
    }

    @Test func partiallyIntroducedWordIsLearning() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        #expect(policy.status(of: word, now: now) == .learning)
    }

    @Test func bothDirectionsAtThresholdMakeLearned() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 21)
        try promote(word, .ruToEn, intervalDays: 25)
        #expect(policy.status(of: word, now: now) == .learned)
    }

    @Test func shortIntervalInOneDirectionKeepsLearning() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        try promote(word, .ruToEn, intervalDays: 10)
        #expect(policy.status(of: word, now: now) == .learning)
    }

    @Test func relearningStateBlocksLearnedDespiteLongInterval() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        try promote(word, .ruToEn, intervalDays: 30, state: .relearning)
        #expect(policy.status(of: word, now: now) == .learning)
    }

    @Test func recentLapseDemotesToLearning() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        try promote(word, .ruToEn, intervalDays: 30)
        logAgain(context, word: word, at: now.addingTimeInterval(-2 * day))
        #expect(policy.status(of: word, now: now) == .learning)
    }

    @Test func oldLapseOutsideWindowDoesNotBlockLearned() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        try promote(word, .ruToEn, intervalDays: 30)
        logAgain(context, word: word, at: now.addingTimeInterval(-15 * day))
        #expect(policy.status(of: word, now: now) == .learned)
    }

    @Test func customConfigurationIsRespected() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 10)
        try promote(word, .ruToEn, intervalDays: 10)
        logAgain(context, word: word, at: now.addingTimeInterval(-5 * day))

        let strict = MasteryPolicy(configuration: .init(minIntervalDays: 7, recentLapseWindowDays: 30))
        let lenient = MasteryPolicy(configuration: .init(minIntervalDays: 7, recentLapseWindowDays: 3))
        #expect(strict.status(of: word, now: now) == .learning)
        #expect(lenient.status(of: word, now: now) == .learned)
    }

    @Test func learnedWordStillGetsMaintenanceReviews() throws {
        // Learned words never leave the schedule: once their long interval
        // elapses, the session queue serves them like any other review.
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context)
        try promote(word, .enToRu, intervalDays: 30)
        try promote(word, .ruToEn, intervalDays: 30)
        try context.save()
        #expect(policy.status(of: word, now: now) == .learned)

        let afterInterval = now.addingTimeInterval(40 * day)
        let queue = try SessionQueue(context: context, now: afterInterval)
        #expect(queue.remainingCount == 2)
        #expect(queue.nextItem(now: afterInterval)?.word === word)
    }
}
