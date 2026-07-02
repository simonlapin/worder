import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct FreePracticeQueueTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    private func importWords(_ context: ModelContext, count: Int) throws -> [Word] {
        let entries = (1...count).map {
            WordBatchFile.Entry(id: $0, word: "word\($0)", translations: ["слово\($0)"])
        }
        try BatchImporter(context: context)
            .importBatch(WordBatchFile(batchId: "b", title: "t", words: entries), now: now)
        return try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
    }

    private func makeQueue(
        _ context: ModelContext,
        seed: UInt64 = 1,
        spacing: Int = 3
    ) throws -> FreePracticeQueue {
        var rng = SplitMix64(seed: seed)
        return try FreePracticeQueue(
            context: context,
            configuration: .init(sameWordSpacing: spacing),
            now: now,
            using: &rng
        )
    }

    private func drain(_ queue: FreePracticeQueue) -> [(wordId: Int, kind: SessionItem.Kind)] {
        var seen: [(Int, SessionItem.Kind)] = []
        var clock = now
        while let item = queue.nextItem(now: clock) {
            seen.append((item.word.wordId, item.kind))
            queue.markCompleted(item, now: clock)
            clock = clock.addingTimeInterval(10)
        }
        return seen
    }

    @Test func emptyDatabaseYieldsEmptyQueue() throws {
        let queue = try makeQueue(try makeContext())
        #expect(queue.isEmpty)
        #expect(queue.nextItem(now: now) == nil)
    }

    @Test func untouchedWordsGetIntroductionsAndBothExercises() throws {
        let context = try makeContext()
        try importWords(context, count: 5)

        let queue = try makeQueue(context)
        let sequence = drain(queue)

        #expect(sequence.filter { $0.kind == .introduction }.count == 5)
        #expect(sequence.count == 15)
        for id in 1...5 {
            #expect(sequence.contains { $0.wordId == id && $0.kind == .exercise(.enToRu) })
            #expect(sequence.contains { $0.wordId == id && $0.kind == .exercise(.ruToEn) })
        }
    }

    @Test func startedWordsSkipIntroductionButKeepBothDirections() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 3)
        let state = try #require(words[0].directionState(for: .enToRu))
        state.state = .review
        state.due = now.addingTimeInterval(86_400)
        try context.save()

        let queue = try makeQueue(context)
        let sequence = drain(queue)

        #expect(!sequence.contains { $0.wordId == 1 && $0.kind == .introduction })
        #expect(sequence.filter { $0.wordId == 1 }.count == 2)
        #expect(sequence.filter { $0.kind == .introduction }.count == 2)
    }

    @Test func wholeDictionaryIsCoveredRegardlessOfDueDates() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 10)
        // Far-future due dates would exclude everything from a scheduled
        // session; free practice must not care.
        for word in words {
            for state in word.directionStates {
                state.state = .review
                state.due = now.addingTimeInterval(30 * 86_400)
            }
        }
        try context.save()

        let queue = try makeQueue(context)
        #expect(queue.remainingCount == 20)
        #expect(Set(drain(queue).map(\.wordId)) == Set(1...10))
    }

    @Test func orderIsShuffledDeterministicallyBySeed() throws {
        let context = try makeContext()
        try importWords(context, count: 30)

        let first = try makeQueue(context, seed: 7).nextItem(now: now)
        let second = try makeQueue(context, seed: 7).nextItem(now: now)
        #expect(first == second)

        let differentSeeds = try (1...10).map {
            try #require(makeQueue(context, seed: UInt64($0)).nextItem(now: now)).word.wordId
        }
        #expect(Set(differentSeeds).count > 1)
    }

    @Test func failedItemReturnsUntilCompleted() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 1)
        let state = try #require(words[0].directionState(for: .enToRu))
        state.state = .learning
        try context.save()

        let queue = try makeQueue(context)
        let first = try #require(queue.nextItem(now: now))
        queue.markFailed(first, now: now)

        #expect(queue.remainingCount == 2)
        let retried = try #require(queue.nextItem(now: now.addingTimeInterval(120)))
        _ = retried
        var clock = now.addingTimeInterval(120)
        var safety = 0
        while let item = queue.nextItem(now: clock), safety < 10 {
            queue.markCompleted(item, now: clock)
            clock = clock.addingTimeInterval(10)
            safety += 1
        }
        #expect(queue.isEmpty)
    }

    @Test func sameWordItemsAreSpacedApart() throws {
        let context = try makeContext()
        let words = try importWords(context, count: 10)
        for word in words {
            let state = try #require(word.directionState(for: .enToRu))
            state.state = .review
        }
        try context.save()

        let sequence = drain(try makeQueue(context))
        for (index, entry) in sequence.enumerated() where index >= 3 {
            let window = sequence[(index - 3)..<index]
            if index < sequence.count - 7 {
                #expect(!window.contains { $0.wordId == entry.wordId },
                        "word \(entry.wordId) repeated too soon at \(index)")
            }
        }
    }
}

@Suite struct SessionQueueFreeLogInteractionTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    @Test func freePracticeLogsDoNotConsumeTheDailyNewWordBudget() throws {
        let context = try makeContext()
        let entries = (1...3).map {
            WordBatchFile.Entry(id: $0, word: "word\($0)", translations: ["слово\($0)"])
        }
        try BatchImporter(context: context)
            .importBatch(WordBatchFile(batchId: "b", title: "t", words: entries), now: now)
        let words = try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))

        // Free practice touched every word today; direction states stay new.
        for word in words {
            let log = ReviewLog(reviewedAt: now.addingTimeInterval(-600), direction: .enToRu, grade: .good, isFreePractice: true)
            context.insert(log)
            log.word = word
        }
        try context.save()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let queue = try SessionQueue(
            context: context,
            configuration: .init(dailyNewWordLimit: 2),
            calendar: calendar,
            now: now
        )
        #expect(queue.plannedNewWords.count == 2)
    }
}

@Suite struct FreePracticeWeightTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try WorderModelContainer.make(inMemory: true))
    }

    private func makeWord(_ context: ModelContext, id: Int, isLeech: Bool = false) -> Word {
        let word = Word(wordId: id, text: "word\(id)", translations: ["слово\(id)"], isLeech: isLeech)
        context.insert(word)
        for direction in Direction.allCases {
            let state = DirectionState(direction: direction, due: now)
            context.insert(state)
            state.word = word
        }
        return word
    }

    private func logAnswer(_ context: ModelContext, word: Word, grade: ReviewGrade, daysAgo: Double, free: Bool = false) {
        let log = ReviewLog(
            reviewedAt: now.addingTimeInterval(-daysAgo * 86_400),
            direction: .enToRu,
            grade: grade,
            isFreePractice: free
        )
        context.insert(log)
        log.word = word
    }

    private let configuration = FreePracticeQueue.Configuration()

    @Test func leechesAndRecentFailuresWeighMoreThanFreshWords() throws {
        let context = try makeContext()
        let plain = makeWord(context, id: 1)
        let leech = makeWord(context, id: 2, isLeech: true)
        let failed = makeWord(context, id: 3)
        logAnswer(context, word: failed, grade: .again, daysAgo: 1, free: true)

        let plainWeight = FreePracticeQueue.weight(of: plain, now: now, configuration: configuration)
        #expect(FreePracticeQueue.weight(of: leech, now: now, configuration: configuration) > plainWeight)
        #expect(FreePracticeQueue.weight(of: failed, now: now, configuration: configuration) > plainWeight)
    }

    @Test func oldFailuresOutsideWindowDoNotCount() throws {
        let context = try makeContext()
        let word = makeWord(context, id: 1)
        logAnswer(context, word: word, grade: .again, daysAgo: 30)

        let fresh = makeWord(context, id: 2)
        #expect(FreePracticeQueue.weight(of: word, now: now, configuration: configuration)
            == FreePracticeQueue.weight(of: fresh, now: now, configuration: configuration))
        #expect(!FreePracticeQueue.hasRecentFailure(word, now: now, configuration: configuration))
    }

    @Test func solidlyLearnedWordsWeighLessThanFragileOnes() throws {
        let context = try makeContext()
        let solid = makeWord(context, id: 1)
        for state in solid.directionStates {
            state.state = .review
            state.stability = 30
        }
        let fragile = makeWord(context, id: 2)
        for state in fragile.directionStates {
            state.state = .review
            state.stability = 2
        }

        #expect(FreePracticeQueue.weight(of: solid, now: now, configuration: configuration)
            < FreePracticeQueue.weight(of: fragile, now: now, configuration: configuration))
    }

    @Test func recentlyFailedWordGetsASecondExercisePass() throws {
        let context = try makeContext()
        let entries = (1...4).map {
            WordBatchFile.Entry(id: $0, word: "word\($0)", translations: ["слово\($0)"])
        }
        try BatchImporter(context: context)
            .importBatch(WordBatchFile(batchId: "b", title: "t", words: entries), now: now)
        let words = try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
        // Word 1 was answered before (so no intro) and failed recently.
        let state = try #require(words[0].directionState(for: .enToRu))
        state.state = .learning
        logAnswer(context, word: words[0], grade: .again, daysAgo: 1, free: true)
        try context.save()

        var rng = SplitMix64(seed: 3)
        let queue = try FreePracticeQueue(context: context, now: now, using: &rng)

        var counts: [Int: Int] = [:]
        var clock = now
        while let item = queue.nextItem(now: clock) {
            if case .exercise = item.kind {
                counts[item.word.wordId, default: 0] += 1
            }
            queue.markCompleted(item, now: clock)
            clock = clock.addingTimeInterval(10)
        }
        #expect(counts[1] == 4)
        #expect(counts.filter { $0.key != 1 }.allSatisfy { $0.value == 2 })
    }

    @Test func weakWordSurfacesEarlierOnAverageAcrossSeeds() throws {
        let context = try makeContext()
        let entries = (1...20).map {
            WordBatchFile.Entry(id: $0, word: "word\($0)", translations: ["слово\($0)"])
        }
        try BatchImporter(context: context)
            .importBatch(WordBatchFile(batchId: "b", title: "t", words: entries), now: now)
        let words = try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.wordId)]))
        // Word 1: leech with a fresh failure — maximum weight.
        words[0].isLeech = true
        let state = try #require(words[0].directionState(for: .enToRu))
        state.state = .learning
        state.stability = 1
        logAnswer(context, word: words[0], grade: .again, daysAgo: 1, free: true)
        try context.save()

        var weakPositions = 0
        var referencePositions = 0
        for seed in 1...20 {
            var rng = SplitMix64(seed: UInt64(seed))
            let queue = try FreePracticeQueue(context: context, now: now, using: &rng)
            var position = 0
            var weakSeen = false
            var referenceSeen = false
            var clock = now
            while let item = queue.nextItem(now: clock), !(weakSeen && referenceSeen) {
                if item.word.wordId == 1, !weakSeen {
                    weakPositions += position
                    weakSeen = true
                }
                if item.word.wordId == 10, !referenceSeen {
                    referencePositions += position
                    referenceSeen = true
                }
                queue.markCompleted(item, now: clock)
                clock = clock.addingTimeInterval(10)
                position += 1
            }
        }
        #expect(weakPositions < referencePositions)
    }
}
