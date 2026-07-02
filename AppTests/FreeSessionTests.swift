import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

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

@MainActor
struct FreeSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private let oneWordJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "dog", "translations": ["собака"]}
        ]
    }
    """.utf8)

    private func makeContainer() throws -> ModelContainer {
        let container = try WorderModelContainer.make(inMemory: true)
        try BatchImporter(context: ModelContext(container))
            .importBatch(from: oneWordJSON, now: t0.addingTimeInterval(-86_400))
        return container
    }

    private func makeFreeModel(context: ModelContext) -> SessionViewModel {
        var configuration = SessionViewModel.Configuration()
        configuration.mode = .free
        return SessionViewModel(
            context: context,
            configuration: configuration,
            speech: MockSpeechService(isAvailable: false),
            rng: SplitMix64(seed: 1),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func answerCurrentExercise(_ model: SessionViewModel, correct: Bool, now: Date) throws {
        guard case .exercise = model.phase else {
            throw TestAbort("expected exercise, got \(model.phase)")
        }
        model.submitTypedAnswer(correct ? currentAnswer(model) : "чепуха", now: now)
        model.continueAfterFeedback(now: now.addingTimeInterval(1))
    }

    private func currentAnswer(_ model: SessionViewModel) -> String {
        guard case .exercise(let exercise) = model.phase else { return "" }
        return exercise.direction == .enToRu ? "собака" : "dog"
    }

    @Test func freeAnswersNeverTouchTheSchedule() throws {
        let container = try makeContainer()
        let model = makeFreeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        try answerCurrentExercise(model, correct: true, now: t0.addingTimeInterval(5))
        try answerCurrentExercise(model, correct: false, now: t0.addingTimeInterval(10))

        let context = ModelContext(container)
        let states = try context.fetch(FetchDescriptor<DirectionState>())
        #expect(states.allSatisfy { $0.state == .new && $0.reps == 0 && $0.lapses == 0 })

        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { $0.isFreePractice })

        let session = try #require(try context.fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.mode == .free)
        #expect(session.answersTotal == 2)
        #expect(session.answersCorrect == 1)
        #expect(session.newWordsIntroduced == 0)
    }

    @Test func freeRoundEndsWithSummaryAndFinishedSession() throws {
        let container = try makeContainer()
        let model = makeFreeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        var clock = t0.addingTimeInterval(5)
        var safety = 0
        while case .exercise = model.phase, safety < 20 {
            try answerCurrentExercise(model, correct: true, now: clock)
            clock = clock.addingTimeInterval(10)
            safety += 1
        }

        #expect(model.phase == .finished)
        let summary = try #require(model.summary)
        #expect(summary.answersTotal == 2)
        #expect(summary.newWordsIntroduced == 0)
        let session = try #require(try ModelContext(container).fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.endedAt != nil)
    }

    @Test func freeSessionHasNoSoftTimer() throws {
        let container = try makeContainer()
        let model = makeFreeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        // Two hours in, the session must still be serving exercises.
        let late = t0.addingTimeInterval(2 * 3600)
        try answerCurrentExercise(model, correct: true, now: late)
        guard case .exercise = model.phase else {
            throw TestAbort("expected exercise after 2h, got \(model.phase)")
        }
    }

    @Test func scheduledSessionAfterFreePracticeStillIntroducesTheWord() throws {
        let container = try makeContainer()
        let free = makeFreeModel(context: ModelContext(container))
        free.start(now: t0)
        free.completeIntroduction(now: t0)
        try answerCurrentExercise(free, correct: true, now: t0.addingTimeInterval(5))
        free.endSession(now: t0.addingTimeInterval(10))

        var configuration = SessionViewModel.Configuration()
        configuration.queue.sameWordSpacing = 0
        let scheduled = SessionViewModel(
            context: ModelContext(container),
            configuration: configuration,
            speech: MockSpeechService(isAvailable: false),
            rng: SplitMix64(seed: 1),
            calendar: Calendar(identifier: .gregorian)
        )
        let later = t0.addingTimeInterval(3600)
        scheduled.start(now: later)
        // The word was only free-practiced: it is still new to the schedule.
        guard case .introduction = scheduled.phase else {
            throw TestAbort("expected introduction, got \(scheduled.phase)")
        }
        scheduled.completeIntroduction(now: later)
        scheduled.submitTypedAnswer("собака", now: later.addingTimeInterval(5))

        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<StudySession>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(sessions.count == 2)
        #expect(sessions[1].mode == .scheduled)
        #expect(sessions[1].newWordsIntroduced == 1)

        let movedStates = try context.fetch(FetchDescriptor<DirectionState>(
            predicate: #Predicate { $0.stateRaw != "new" }
        ))
        #expect(movedStates.count == 1)
    }
}
