import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@MainActor
struct HomeViewModelTests {
    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "ring", "translations": ["кольцо", "звонить"]},
            {"id": 3, "word": "plane", "translations": ["самолёт"]}
        ]
    }
    """.utf8)

    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    private func makeSettings(limit: Int = AppSettings.dailyNewWordLimitDefault) -> AppSettings {
        let suiteName = "HomeViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.dailyNewWordLimit = limit
        return settings
    }

    private func makeModel(context: ModelContext, limit: Int = AppSettings.dailyNewWordLimitDefault, calendar: Calendar = .current) -> HomeViewModel {
        HomeViewModel(context: context, settings: makeSettings(limit: limit), calendar: calendar)
    }

    @Test func freshImportCountsAllWordsAsNewAndNoneAsDue() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)

        let model = makeModel(context: context)
        model.refresh(now: now)

        #expect(model.dueReviewCount == 0)
        #expect(model.newWordsTodayCount == 3)
        #expect(model.streakDays == 0)
        #expect(model.hasWorkAvailable)
        #expect(model.loadFailureMessage == nil)
    }

    @Test func overdueReviewStatesAreCountedSeparatelyFromNewWords() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)

        let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.wordId == 1 }))
        let word = try #require(words.first)
        for state in word.directionStates {
            state.state = .review
            state.due = now.addingTimeInterval(-3600)
        }
        try context.save()

        let model = makeModel(context: context)
        model.refresh(now: now)

        #expect(model.dueReviewCount == 2)
        #expect(model.newWordsTodayCount == 2)
    }

    @Test func newWordCountRespectsSettingsLimit() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)

        let model = makeModel(context: context, limit: 2)
        model.refresh(now: now)
        #expect(model.newWordsTodayCount == 2)

        let zeroModel = makeModel(context: context, limit: 0)
        zeroModel.refresh(now: now)
        #expect(zeroModel.newWordsTodayCount == 0)
        #expect(!zeroModel.hasWorkAvailable)
    }

    @Test func emptyDatabaseHasNoWorkAvailable() throws {
        let context = try makeContext()

        let model = makeModel(context: context)
        model.refresh(now: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(model.dueReviewCount == 0)
        #expect(model.newWordsTodayCount == 0)
        #expect(!model.hasWorkAvailable)
    }

    @Test func streakCountsConsecutiveDaysEndingToday() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        for daysAgo in 0...2 {
            insertFinishedSession(into: context, daysAgo: daysAgo, from: now, calendar: calendar)
        }
        try context.save()

        let model = makeModel(context: context, calendar: calendar)
        model.refresh(now: now)

        #expect(model.streakDays == 3)
    }

    @Test func streakSurvivesWhenTodayHasNoSessionYet() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        insertFinishedSession(into: context, daysAgo: 1, from: now, calendar: calendar)
        insertFinishedSession(into: context, daysAgo: 2, from: now, calendar: calendar)
        try context.save()

        let model = makeModel(context: context, calendar: calendar)
        model.refresh(now: now)

        #expect(model.streakDays == 2)
    }

    @Test func streakBreaksAfterAMissedDay() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        insertFinishedSession(into: context, daysAgo: 2, from: now, calendar: calendar)
        insertFinishedSession(into: context, daysAgo: 3, from: now, calendar: calendar)
        try context.save()

        let model = makeModel(context: context, calendar: calendar)
        model.refresh(now: now)

        #expect(model.streakDays == 0)
    }

    @Test func unfinishedSessionDoesNotCountTowardStreak() throws {
        let context = try makeContext()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        context.insert(StudySession(startedAt: now))
        try context.save()

        let model = makeModel(context: context, calendar: calendar)
        model.refresh(now: now)

        #expect(model.streakDays == 0)
    }

    private func insertFinishedSession(
        into context: ModelContext,
        daysAgo: Int,
        from now: Date,
        calendar: Calendar
    ) {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        context.insert(StudySession(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            answersTotal: 10,
            answersCorrect: 8
        ))
    }
}

@MainActor
struct AppBootstrapTests {
    @Test func bundledBatchImportsAllWordsAndIsIdempotent() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let first = try AppBootstrap.importBundledBatch(into: context, now: now)
        #expect(first.insertedWords == 1500)

        let second = try AppBootstrap.importBundledBatch(into: context, now: now)
        #expect(second.insertedWords == 0)
        #expect(second.updatedWords == 0)
        #expect(second.unchangedWords == 1500)
    }

    @Test func missingResourceProducesTypedError() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let emptyBundle = Bundle(for: BundleMarker.self)

        #expect(throws: AppBootstrap.BootstrapError.self) {
            try AppBootstrap.importBundledBatch(into: context, from: emptyBundle, now: .now)
        }
    }
}

private final class BundleMarker {}
