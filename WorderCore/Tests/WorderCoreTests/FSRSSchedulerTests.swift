import Foundation
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let day: TimeInterval = 86_400

private func newCard() -> SchedulerCard {
    SchedulerCard(due: now)
}

@Suite struct FSRSSchedulerTests {
    private let scheduler = FSRSScheduler()

    @Test func firstGoodMovesNewCardIntoReviewWithFutureDue() throws {
        let card = try scheduler.next(card: newCard(), grade: .good, now: now)

        #expect(card.state == .review)
        #expect(card.due > now)
        #expect(card.reps == 1)
        #expect(card.lapses == 0)
        #expect(card.stability > 0)
        #expect(card.difficulty > 0)
        #expect(card.lastReviewedAt == now)
    }

    @Test func intervalsGrowUnderRepeatedGood() throws {
        var card = newCard()
        var reviewedAt = now
        var previousInterval: TimeInterval = 0

        for _ in 1...4 {
            card = try scheduler.next(card: card, grade: .good, now: reviewedAt)
            let interval = card.due.timeIntervalSince(reviewedAt)
            #expect(interval > previousInterval)
            previousInterval = interval
            reviewedAt = card.due
        }
        #expect(card.reps == 4)
        #expect(previousInterval >= 7 * day)
    }

    @Test func againResetsIntervalAndIncrementsLapses() throws {
        var card = newCard()
        var reviewedAt = now
        for _ in 1...3 {
            card = try scheduler.next(card: card, grade: .good, now: reviewedAt)
            reviewedAt = card.due
        }
        let matureInterval = card.due.timeIntervalSince(card.lastReviewedAt ?? now)

        let failed = try scheduler.next(card: card, grade: .again, now: reviewedAt)

        #expect(failed.lapses == card.lapses + 1)
        #expect(failed.due.timeIntervalSince(reviewedAt) < matureInterval)
        #expect(failed.stability < card.stability)
    }

    @Test func gradeOrderingIsMonotonic() throws {
        var card = newCard()
        card = try scheduler.next(card: card, grade: .good, now: now)
        let reviewedAt = card.due

        let again = try scheduler.next(card: card, grade: .again, now: reviewedAt)
        let hard = try scheduler.next(card: card, grade: .hard, now: reviewedAt)
        let good = try scheduler.next(card: card, grade: .good, now: reviewedAt)
        let easy = try scheduler.next(card: card, grade: .easy, now: reviewedAt)

        #expect(again.due < hard.due)
        #expect(hard.due < good.due)
        #expect(good.due < easy.due)
    }

    @Test func schedulingIsDeterministic() throws {
        let first = try scheduler.next(card: newCard(), grade: .good, now: now)
        let second = try scheduler.next(card: newCard(), grade: .good, now: now)
        #expect(first == second)
    }

    @Test func desiredRetentionAffectsIntervals() throws {
        let strict = FSRSScheduler(desiredRetention: 0.97)
        let relaxed = FSRSScheduler(desiredRetention: 0.8)

        var strictCard = try strict.next(card: newCard(), grade: .good, now: now)
        var relaxedCard = try relaxed.next(card: newCard(), grade: .good, now: now)
        strictCard = try strict.next(card: strictCard, grade: .good, now: strictCard.due)
        relaxedCard = try relaxed.next(card: relaxedCard, grade: .good, now: relaxedCard.due)

        let strictInterval = strictCard.due.timeIntervalSince(strictCard.lastReviewedAt ?? now)
        let relaxedInterval = relaxedCard.due.timeIntervalSince(relaxedCard.lastReviewedAt ?? now)
        #expect(strictInterval < relaxedInterval)
    }
}

@Suite struct DirectionStateSchedulerBridgeTests {
    @Test func snapshotAndApplyRoundTrip() throws {
        let state = DirectionState(direction: .enToRu, due: now)
        let scheduler = FSRSScheduler()

        let updated = try scheduler.next(card: state.schedulerCard, grade: .good, now: now)
        state.apply(updated)

        #expect(state.state == updated.state)
        #expect(state.stability == updated.stability)
        #expect(state.difficulty == updated.difficulty)
        #expect(state.due == updated.due)
        #expect(state.lapses == updated.lapses)
        #expect(state.reps == updated.reps)
        #expect(state.lastReviewedAt == updated.lastReviewedAt)
        #expect(state.schedulerCard == updated)
    }
}
