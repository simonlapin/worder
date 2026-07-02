import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
struct WordBrowserViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let day: TimeInterval = 86_400

    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "plane", "translations": ["самолёт"]},
            {"id": 3, "word": "dog", "translations": ["собака"]}
        ]
    }
    """.utf8)

    private func makeModel() throws -> (WordBrowserViewModel, ModelContext) {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now.addingTimeInterval(-30 * day))
        let model = WordBrowserViewModel(context: context)
        return (model, context)
    }

    private func promote(_ context: ModelContext, wordId: Int, stability: Double, dueInDays: Double) throws {
        let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.wordId == wordId }))
        for state in try #require(words.first).directionStates {
            state.state = .review
            state.stability = stability
            state.lastReviewedAt = now.addingTimeInterval(-day)
            state.due = now.addingTimeInterval(dueInDays * day)
        }
    }

    private func log(_ context: ModelContext, wordId: Int, grade: ReviewGrade, free: Bool = false) throws {
        let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.wordId == wordId }))
        let log = ReviewLog(reviewedAt: now.addingTimeInterval(-3600), direction: .enToRu, grade: grade, isFreePractice: free)
        context.insert(log)
        log.word = try #require(words.first)
    }

    @Test func rowsExposeStatusErrorRateAndNextDue() throws {
        let (model, context) = try makeModel()
        try promote(context, wordId: 1, stability: 30, dueInDays: 29)
        try log(context, wordId: 1, grade: .good)
        try log(context, wordId: 1, grade: .again, free: true)
        try context.save()

        model.refresh(now: now)
        let shop = try #require(model.visibleRows.first { $0.wordId == 1 })

        // The fresh `again` (free practice included) blocks learned status by design.
        #expect(shop.status == .learning)
        #expect(shop.answersTotal == 2)
        #expect(shop.answersWrong == 1)
        #expect(shop.errorRate == 0.5)
        #expect(shop.nextDue == now.addingTimeInterval(29 * day))

        let dog = try #require(model.visibleRows.first { $0.wordId == 3 })
        #expect(dog.status == .new)
        #expect(dog.errorRate == nil)
        #expect(dog.nextDue == nil)
        #expect(model.totalCount == 3)
    }

    @Test func alphabeticalSortIsDefault() throws {
        let (model, _) = try makeModel()
        model.refresh(now: now)
        #expect(model.visibleRows.map(\.text) == ["dog", "plane", "shop"])
    }

    @Test func statusSortPutsLearningFirstAndNewLast() throws {
        let (model, context) = try makeModel()
        try promote(context, wordId: 1, stability: 30, dueInDays: 29)
        try promote(context, wordId: 2, stability: 2, dueInDays: 1)
        try context.save()

        model.refresh(now: now)
        model.sortOrder = .status
        #expect(model.visibleRows.map(\.wordId) == [2, 1, 3])
    }

    @Test func errorRateSortPutsProblematicWordsFirst() throws {
        let (model, context) = try makeModel()
        try log(context, wordId: 2, grade: .again)
        try log(context, wordId: 2, grade: .again)
        try log(context, wordId: 1, grade: .good)
        try log(context, wordId: 1, grade: .again)
        try context.save()

        model.refresh(now: now)
        model.sortOrder = .errorRate
        #expect(model.visibleRows.map(\.wordId) == [2, 1, 3])
    }

    @Test func nextReviewSortOrdersByDueWithNewWordsLast() throws {
        let (model, context) = try makeModel()
        try promote(context, wordId: 1, stability: 5, dueInDays: 5)
        try promote(context, wordId: 2, stability: 2, dueInDays: 1)
        try context.save()

        model.refresh(now: now)
        model.sortOrder = .nextReview
        #expect(model.visibleRows.map(\.wordId) == [2, 1, 3])
    }

    @Test func frequencySortUsesWordId() throws {
        let (model, _) = try makeModel()
        model.refresh(now: now)
        model.sortOrder = .frequency
        #expect(model.visibleRows.map(\.wordId) == [1, 2, 3])
    }

    @Test func searchMatchesWordAndTranslationWithYoNormalization() throws {
        let (model, _) = try makeModel()
        model.refresh(now: now)

        model.searchText = "SHO"
        #expect(model.visibleRows.map(\.wordId) == [1])

        // «самолёт» stored with ё must match a plain «е» query.
        model.searchText = "самолет"
        #expect(model.visibleRows.map(\.wordId) == [2])

        model.searchText = "нету такого"
        #expect(model.visibleRows.isEmpty)

        model.searchText = ""
        #expect(model.visibleRows.count == 3)
    }

    @Test func wordLookupReturnsModelForDetailScreen() throws {
        let (model, _) = try makeModel()
        model.refresh(now: now)
        let row = try #require(model.visibleRows.first)
        #expect(model.word(for: row.id)?.text == row.text)
    }
}
