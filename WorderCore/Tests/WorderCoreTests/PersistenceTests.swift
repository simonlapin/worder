import Foundation
import SwiftData
import Testing
@testable import WorderCore

private func makeContext() throws -> ModelContext {
    ModelContext(try WorderModelContainer.make(inMemory: true))
}

private let now = Date(timeIntervalSince1970: 1_750_000_000)

@discardableResult
private func insertWord(
    _ context: ModelContext,
    batch: Batch,
    wordId: Int = 1,
    text: String = "shop",
    translations: [String] = ["магазин"]
) -> Word {
    let word = Word(wordId: wordId, text: text, translations: translations)
    context.insert(word)
    word.batch = batch
    for direction in Direction.allCases {
        let state = DirectionState(direction: direction, due: now)
        context.insert(state)
        state.word = word
    }
    return word
}

@Suite struct PersistenceCRUDTests {
    @Test func savesAndFetchesBatchWithWords() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "core-1500", title: "Core 1500", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        insertWord(context, batch: batch, wordId: 42, text: "ring", translations: ["кольцо", "звонить"])
        try context.save()

        let batches = try context.fetch(FetchDescriptor<Batch>())
        #expect(batches.count == 1)
        #expect(batches[0].batchId == "core-1500")
        #expect(batches[0].words.count == 1)

        let word = try #require(batches[0].words.first)
        #expect(word.wordId == 42)
        #expect(word.text == "ring")
        #expect(word.translations == ["кольцо", "звонить"])
        #expect(word.note == nil)
        #expect(!word.isLeech)
        #expect(word.leechHint == nil)
        #expect(word.batch?.batchId == "core-1500")

        word.leechHint = "Кольцо на пальце — ring, звонок — тоже ring."
        try context.save()
        #expect(batches[0].words.first?.leechHint?.isEmpty == false)
    }

    @Test func directionStatesRoundTripEnumsAndFSRSFields() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        let word = insertWord(context, batch: batch)

        let enToRu = try #require(word.directionState(for: .enToRu))
        enToRu.state = .review
        enToRu.stability = 12.5
        enToRu.difficulty = 4.2
        enToRu.due = now.addingTimeInterval(86_400 * 10)
        enToRu.lapses = 2
        enToRu.reps = 7
        enToRu.lastReviewedAt = now
        try context.save()

        let states = try context.fetch(FetchDescriptor<DirectionState>())
        #expect(states.count == 2)
        #expect(Set(states.map(\.direction)) == Set(Direction.allCases))

        let reloaded = try #require(states.first { $0.direction == .enToRu })
        #expect(reloaded.state == .review)
        #expect(reloaded.stability == 12.5)
        #expect(reloaded.difficulty == 4.2)
        #expect(reloaded.due == now.addingTimeInterval(86_400 * 10))
        #expect(reloaded.lapses == 2)
        #expect(reloaded.reps == 7)
        #expect(reloaded.lastReviewedAt == now)

        let fresh = try #require(states.first { $0.direction == .ruToEn })
        #expect(fresh.state == .new)
        #expect(fresh.reps == 0)
    }

    @Test func directionStatesAreQueryableByRawFieldsInPredicates() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        let word = insertWord(context, batch: batch)
        try #require(word.directionState(for: .enToRu)).due = now.addingTimeInterval(-60)
        try #require(word.directionState(for: .ruToEn)).due = now.addingTimeInterval(60)
        try context.save()

        let directionRaw = Direction.enToRu.rawValue
        let dueBefore = now
        let descriptor = FetchDescriptor<DirectionState>(
            predicate: #Predicate { $0.directionRaw == directionRaw && $0.due <= dueBefore }
        )
        let due = try context.fetch(descriptor)
        #expect(due.count == 1)
        #expect(due[0].direction == .enToRu)
    }

    @Test func reviewLogAndCachedSentenceAttachToWord() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        let word = insertWord(context, batch: batch)

        let log = ReviewLog(reviewedAt: now, direction: .ruToEn, grade: .hard)
        context.insert(log)
        log.word = word
        let sentence = CachedSentence(en: "I went to the shop.", ru: "Я пошёл в магазин.", createdAt: now)
        context.insert(sentence)
        sentence.word = word
        try context.save()

        #expect(word.reviewLogs.count == 1)
        #expect(word.reviewLogs[0].direction == .ruToEn)
        #expect(word.reviewLogs[0].grade == .hard)
        #expect(word.sentences.count == 1)
        #expect(word.sentences[0].en == "I went to the shop.")
    }

    @Test func studySessionRoundTrips() throws {
        let context = try makeContext()
        let session = StudySession(startedAt: now, answersTotal: 30, answersCorrect: 27, newWordsIntroduced: 5)
        context.insert(session)
        session.endedAt = now.addingTimeInterval(1_800)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1)
        #expect(sessions[0].answersTotal == 30)
        #expect(sessions[0].answersCorrect == 27)
        #expect(sessions[0].newWordsIntroduced == 5)
        #expect(sessions[0].endedAt == now.addingTimeInterval(1_800))
    }
}

@Suite struct PersistenceCascadeTests {
    @Test func deletingWordCascadesToStatesLogsAndSentences() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        let word = insertWord(context, batch: batch)
        let log = ReviewLog(reviewedAt: now, direction: .enToRu, grade: .good)
        context.insert(log)
        log.word = word
        let sentence = CachedSentence(en: "En.", ru: "Ру.", createdAt: now)
        context.insert(sentence)
        sentence.word = word
        try context.save()

        context.delete(word)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Word>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedSentence>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test func deletingBatchCascadesThroughWords() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        insertWord(context, batch: batch, wordId: 1, text: "shop")
        insertWord(context, batch: batch, wordId: 2, text: "store")
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).count == 4)

        context.delete(batch)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Batch>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Word>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).isEmpty)
    }

    @Test func deletingWordDoesNotDeleteSiblings() throws {
        let context = try makeContext()
        let batch = Batch(batchId: "b", title: "t", schemaVersion: 1, importedAt: now)
        context.insert(batch)
        let shop = insertWord(context, batch: batch, wordId: 1, text: "shop")
        insertWord(context, batch: batch, wordId: 2, text: "store")
        try context.save()

        context.delete(shop)
        try context.save()

        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.map(\.text) == ["store"])
        #expect(try context.fetch(FetchDescriptor<DirectionState>()).count == 2)
    }
}
