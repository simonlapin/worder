import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
struct StatsViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "ring", "translations": ["кольцо", "звонить"]}
        ]
    }
    """.utf8)

    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    @Test func refreshExposesSnapshotFromDatabase() throws {
        let context = try makeContext()
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)
        context.insert(StudySession(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            answersTotal: 4,
            answersCorrect: 3
        ))
        try context.save()

        let model = StatsViewModel(context: context)
        model.refresh(now: now)

        #expect(model.loadFailureMessage == nil)
        #expect(model.snapshot.totals == .init(new: 2))
        #expect(model.snapshot.batches.map(\.title) == ["Test Batch"])
        #expect(model.snapshot.recentSessions.count == 1)
        #expect(model.snapshot.streakDays == 1)
    }

    @Test func emptyDatabaseYieldsEmptySnapshotWithoutError() throws {
        let context = try makeContext()

        let model = StatsViewModel(context: context)
        model.refresh(now: now)

        #expect(model.loadFailureMessage == nil)
        #expect(model.snapshot == StatsSnapshot())
        #expect(model.learnedFraction == 0)
    }

    @Test func learnedFractionReflectsLearnedShare() throws {
        let context = try makeContext()
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)
        let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.wordId == 1 }))
        let word = try #require(words.first)
        for state in word.directionStates {
            state.state = .review
            state.lastReviewedAt = now.addingTimeInterval(-86_400)
            state.due = now.addingTimeInterval(29 * 86_400)
            state.reps = 5
        }
        try context.save()

        let model = StatsViewModel(context: context)
        model.refresh(now: now)

        #expect(model.snapshot.totals == .init(new: 1, learned: 1))
        #expect(model.learnedFraction == 0.5)
    }
}
