import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)
private let day: TimeInterval = 86_400

@Suite struct StateBackupTests {
    private let exporter = StateExporter()
    private let importer = StateImporter()
    private let settings = StateBackup.Settings(
        dailyNewWordLimit: 15,
        remindersEnabled: true,
        reminderTimes: [540, 1200]
    )

    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    private func populate(_ context: ModelContext) throws {
        let batch = Batch(batchId: "core", title: "Core", schemaVersion: 1, importedAt: now.addingTimeInterval(-30 * day))
        context.insert(batch)

        let shop = Word(
            wordId: 1,
            text: "shop",
            translations: ["магазин", "лавка"],
            note: "noun",
            category: "commerce",
            isLeech: true,
            leechHint: "shop is smaller than store"
        )
        context.insert(shop)
        shop.batch = batch

        let ring = Word(wordId: 2, text: "ring", translations: ["кольцо", "звонить"])
        context.insert(ring)
        ring.batch = batch

        for (direction, stability) in zip(Direction.allCases, [12.5, 3.25]) {
            let state = DirectionState(
                direction: direction,
                state: .review,
                stability: stability,
                difficulty: 4.75,
                due: now.addingTimeInterval(stability * day),
                lapses: 2,
                reps: 9,
                lastReviewedAt: now.addingTimeInterval(-day)
            )
            context.insert(state)
            state.word = shop
        }

        let log = ReviewLog(reviewedAt: now.addingTimeInterval(-day), direction: .ruToEn, grade: .hard)
        context.insert(log)
        log.word = shop

        let sentence = CachedSentence(en: "I went to the shop.", ru: "Я пошёл в магазин.", createdAt: now.addingTimeInterval(-2 * day))
        context.insert(sentence)
        sentence.word = shop

        context.insert(StudySession(
            startedAt: now.addingTimeInterval(-day),
            endedAt: now.addingTimeInterval(-day + 600),
            answersTotal: 12,
            answersCorrect: 10,
            newWordsIntroduced: 3
        ))
        context.insert(StudySession(startedAt: now))

        try context.save()
    }

    @Test func roundTripRestoresEquivalentState() throws {
        let source = try makeContext()
        try populate(source)

        let data = try exporter.export(from: source, settings: settings, now: now)
        let target = try makeContext()
        let restoredBackup = try importer.importState(data, into: target)

        #expect(restoredBackup.settings == settings)

        let reExported = try exporter.export(from: target, settings: settings, now: now)
        #expect(data == reExported)

        let words = try target.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
        #expect(words.count == 2)
        let shop = try #require(words.first)
        #expect(shop.text == "shop")
        #expect(shop.translations == ["магазин", "лавка"])
        #expect(shop.isLeech)
        #expect(shop.leechHint == "shop is smaller than store")
        #expect(shop.directionStates.count == 2)
        #expect(shop.reviewLogs.map(\.grade) == [.hard])
        #expect(shop.sentences.map(\.en) == ["I went to the shop."])
        #expect(shop.batch?.batchId == "core")

        let sessions = try target.fetch(FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(sessions.count == 2)
        #expect(sessions[0].endedAt != nil)
        #expect(sessions[1].endedAt == nil)
    }

    @Test func unbatchedWordsSurviveRoundTrip() throws {
        let source = try makeContext()
        let orphan = Word(wordId: 99, text: "orphan", translations: ["сирота"])
        source.insert(orphan)
        try source.save()

        let data = try exporter.export(from: source, settings: settings, now: now)
        let target = try makeContext()
        try importer.importState(data, into: target)

        let words = try target.fetch(FetchDescriptor<Word>())
        #expect(words.map(\.text) == ["orphan"])
        #expect(words.first?.batch == nil)
    }

    @Test func importIntoNonEmptyDatabaseIsRejected() throws {
        let source = try makeContext()
        try populate(source)
        let data = try exporter.export(from: source, settings: settings, now: now)

        let target = try makeContext()
        target.insert(Word(wordId: 1, text: "existing", translations: ["есть"]))
        try target.save()

        #expect(throws: StateImporter.ImportError.databaseNotEmpty) {
            try importer.importState(data, into: target)
        }
    }

    @Test func eraseAllEmptiesTheDatabaseAndAllowsImport() throws {
        let source = try makeContext()
        try populate(source)
        let data = try exporter.export(from: source, settings: settings, now: now)

        let target = try makeContext()
        try populate(target)
        #expect(try !importer.isDatabaseEmpty(target))

        try importer.eraseAll(in: target)
        #expect(try importer.isDatabaseEmpty(target))
        #expect(try target.fetchCount(FetchDescriptor<DirectionState>()) == 0)
        #expect(try target.fetchCount(FetchDescriptor<ReviewLog>()) == 0)
        #expect(try target.fetchCount(FetchDescriptor<CachedSentence>()) == 0)

        try importer.importState(data, into: target)
        #expect(try target.fetchCount(FetchDescriptor<Word>()) == 2)
    }

    @Test func unsupportedVersionIsRejected() throws {
        let source = try makeContext()
        let data = try exporter.export(from: source, settings: settings, now: now)
        let futureVersion = try #require(
            String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "\"backupVersion\" : 1", with: "\"backupVersion\" : 2")
                .data(using: .utf8)
        )

        #expect(throws: StateImporter.ImportError.unsupportedVersion(2)) {
            try importer.importState(futureVersion, into: try makeContext())
        }
    }

    @Test func malformedDataProducesTypedError() throws {
        let context = try makeContext()
        #expect(throws: StateImporter.ImportError.self) {
            try importer.importState(Data("not json".utf8), into: context)
        }
    }

    @Test func exportedJSONOmitsAPIKeyAndIsDeterministic() throws {
        let source = try makeContext()
        try populate(source)

        let first = try exporter.export(from: source, settings: settings, now: now)
        let second = try exporter.export(from: source, settings: settings, now: now)
        #expect(first == second)

        let text = try #require(String(data: first, encoding: .utf8))
        #expect(!text.lowercased().contains("apikey"))
        #expect(!text.contains("sk-ant"))
        #expect(text.contains("\"backupVersion\" : 1"))
    }
}

@Suite struct StateBackupUnlimitedSettingsTests {
    @Test func nilDailyLimitSurvivesRoundTrip() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let unlimited = StateBackup.Settings(
            dailyNewWordLimit: nil,
            remindersEnabled: false,
            reminderTimes: []
        )
        let data = try StateExporter().export(from: context, settings: unlimited, now: now)
        let restored = try StateImporter().decode(data)
        #expect(restored.settings.dailyNewWordLimit == nil)
        #expect(restored.settings == unlimited)
    }
}
