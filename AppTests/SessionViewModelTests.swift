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
final class MockSpeechService: SpeechService {
    let isAvailable: Bool
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func speak(_ text: String) {
        guard isAvailable else { return }
        spokenTexts.append(text)
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
struct SessionViewModelTests {
    private let sixWordsJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "store", "translations": ["магазин"]},
            {"id": 3, "word": "dog", "translations": ["собака"]},
            {"id": 4, "word": "cat", "translations": ["кошка", "кот"]},
            {"id": 5, "word": "house", "translations": ["дом"]},
            {"id": 6, "word": "plane", "translations": ["самолёт"]}
        ]
    }
    """.utf8)

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

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContainer(importing json: Data?) throws -> ModelContainer {
        let container = try WorderModelContainer.make(inMemory: true)
        if let json {
            try BatchImporter(context: ModelContext(container)).importBatch(from: json, now: t0.addingTimeInterval(-86_400))
        }
        return container
    }

    private func makeModel(
        context: ModelContext,
        configuration: SessionViewModel.Configuration = SessionViewModel.Configuration(),
        speech: MockSpeechService = MockSpeechService(isAvailable: false),
        seed: UInt64 = 1
    ) -> SessionViewModel {
        SessionViewModel(
            context: context,
            configuration: configuration,
            speech: speech,
            rng: SplitMix64(seed: seed),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func introCard(_ model: SessionViewModel) throws -> SessionViewModel.IntroCard {
        guard case .introduction(let card) = model.phase else {
            throw TestAbort("expected introduction, got \(model.phase)")
        }
        return card
    }

    private func exercise(_ model: SessionViewModel) throws -> SessionViewModel.Exercise {
        guard case .exercise(let exercise) = model.phase else {
            throw TestAbort("expected exercise, got \(model.phase)")
        }
        return exercise
    }

    private func feedback(_ model: SessionViewModel) throws -> SessionViewModel.Feedback {
        guard case .feedback(let feedback) = model.phase else {
            throw TestAbort("expected feedback, got \(model.phase)")
        }
        return feedback
    }

    @Test func emptyDatabaseFinishesImmediatelyWithoutSessionRecord() throws {
        let container = try makeContainer(importing: nil)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)

        #expect(model.phase == .finished)
        #expect(model.sessionRecord == nil)
        let sessions = try ModelContext(container).fetch(FetchDescriptor<StudySession>())
        #expect(sessions.isEmpty)
    }

    @Test func introductionExpandsIntoBothDirectionsAndExcludesSharedTranslationOptions() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)
        let card = try introCard(model)
        #expect(card.text == "shop")
        #expect(card.translations == ["магазин"])

        model.completeIntroduction(now: t0)
        let first = try exercise(model)
        #expect(first.direction == .enToRu)
        #expect(first.prompt == "shop")
        guard case .multipleChoice(let ruOptions) = first.input else {
            throw TestAbort("expected multiple choice, got \(first.input)")
        }
        #expect(ruOptions.count == 4)
        #expect(ruOptions.contains("магазин"))
        #expect(Set(ruOptions).count == 4)

        model.submitChoice("магазин", now: t0.addingTimeInterval(5))
        #expect(try feedback(model).verdict == .correct)

        model.continueAfterFeedback(now: t0.addingTimeInterval(10))
        let second = try exercise(model)
        #expect(second.direction == .ruToEn)
        #expect(second.prompt == "магазин")
        guard case .multipleChoice(let enOptions) = second.input else {
            throw TestAbort("expected multiple choice, got \(second.input)")
        }
        #expect(enOptions.contains("shop"))
        #expect(!enOptions.contains("store"))
    }

    @Test func answerIsPersistedImmediatelyAndVisibleFromAnotherContext() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(5))

        let other = ModelContext(container)
        let logs = try other.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.grade == .good)
        #expect(logs.first?.direction == .enToRu)

        let states = try other.fetch(FetchDescriptor<DirectionState>(
            predicate: #Predicate { $0.stateRaw != "new" }
        ))
        #expect(states.count == 1)
        let state = try #require(states.first)
        #expect(state.due > t0)
        #expect(state.reps == 1)

        let session = try #require(other.fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.answersTotal == 1)
        #expect(session.answersCorrect == 1)
        #expect(session.newWordsIntroduced == 1)
        #expect(session.endedAt == nil)
    }

    @Test func wrongAnswerRequeuesUntilAnsweredCorrectly() throws {
        let container = try makeContainer(importing: oneWordJSON)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)

        // A one-word dictionary cannot produce distractors: both exercises
        // degrade to typed answers.
        let first = try exercise(model)
        #expect(first.direction == .enToRu)
        #expect(first.input == .typedAnswer)

        model.submitTypedAnswer("чепуха", now: t0.addingTimeInterval(5))
        let failedFeedback = try feedback(model)
        #expect(failedFeedback.verdict == .wrong)
        #expect(failedFeedback.willRetry)
        #expect(failedFeedback.correctAnswer == "собака")

        model.continueAfterFeedback(now: t0.addingTimeInterval(10))
        let second = try exercise(model)
        #expect(second.direction == .ruToEn)
        model.submitTypedAnswer("dog", now: t0.addingTimeInterval(15))
        model.continueAfterFeedback(now: t0.addingTimeInterval(20))

        // The failed EN→RU exercise returns within the same session.
        let retried = try exercise(model)
        #expect(retried.direction == .enToRu)
        model.submitTypedAnswer("собака", now: t0.addingTimeInterval(25))
        model.continueAfterFeedback(now: t0.addingTimeInterval(30))

        #expect(model.phase == .finished)
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 3)
        let session = try #require(context.fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.answersTotal == 3)
        #expect(session.answersCorrect == 2)
        #expect(session.newWordsIntroduced == 1)
        #expect(session.endedAt != nil)
    }

    @Test func matureRuToEnCardGetsTypedAnswerAndAcceptsSynonym() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let setup = ModelContext(container)
        let shop = try #require(setup.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        let ruToEn = try #require(shop.directionState(for: .ruToEn))
        ruToEn.state = .review
        ruToEn.stability = 5
        ruToEn.due = t0.addingTimeInterval(-3600)
        for state in try setup.fetch(FetchDescriptor<DirectionState>()) where state.state == .new {
            state.due = t0.addingTimeInterval(86_400)
        }
        try setup.save()

        var configuration = SessionViewModel.Configuration()
        configuration.queue = SessionQueue.Configuration(dailyNewWordLimit: 0)
        let model = makeModel(context: ModelContext(container), configuration: configuration)

        model.start(now: t0)
        let exercise = try exercise(model)
        #expect(exercise.direction == .ruToEn)
        #expect(exercise.input == .typedAnswer)

        model.submitTypedAnswer("store", now: t0.addingTimeInterval(5))
        let result = try feedback(model)
        #expect(result.verdict == .correctSynonym(intended: "shop"))
        #expect(!result.willRetry)

        let logs = try ModelContext(container).fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.first?.grade == .good)
    }

    /// Container with shop's card in one direction mature and due, everything
    /// else parked in the future; daily-new limit 0 leaves exactly that one
    /// exercise queued. Optional cached sentences are attached to shop.
    private func makeMatureSetup(
        direction: Direction,
        sentences: [(en: String, ru: String)] = []
    ) throws -> (ModelContainer, SessionViewModel.Configuration) {
        let container = try makeContainer(importing: sixWordsJSON)
        let setup = ModelContext(container)
        let shop = try #require(setup.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        let mature = try #require(shop.directionState(for: direction))
        mature.state = .review
        mature.stability = 25
        mature.due = t0.addingTimeInterval(-3600)
        for state in try setup.fetch(FetchDescriptor<DirectionState>()) where state.state == .new {
            state.due = t0.addingTimeInterval(86_400)
        }
        for sentence in sentences {
            let cached = CachedSentence(en: sentence.en, ru: sentence.ru, createdAt: t0)
            setup.insert(cached)
            cached.word = shop
        }
        try setup.save()

        var configuration = SessionViewModel.Configuration()
        configuration.queue = SessionQueue.Configuration(dailyNewWordLimit: 0)
        return (container, configuration)
    }

    @Test func listeningJoinsRotationForMatureCardWhenVoiceIsAvailable() throws {
        var sawListening = false
        for seed in UInt64(1)...30 {
            let (container, configuration) = try makeMatureSetup(direction: .enToRu)
            let speech = MockSpeechService(isAvailable: true)
            let model = makeModel(
                context: ModelContext(container),
                configuration: configuration,
                speech: speech,
                seed: seed
            )
            model.start(now: t0)

            let exercise = try exercise(model)
            #expect(exercise.direction == .enToRu)
            guard case .listening(let options) = exercise.input else { continue }
            sawListening = true

            #expect(speech.spokenTexts == ["shop"])
            #expect(options.contains("магазин"))
            #expect(!options.contains("store"))

            model.speakCurrentWord()
            #expect(speech.spokenTexts == ["shop", "shop"])

            model.submitChoice("магазин", now: t0.addingTimeInterval(5))
            let result = try feedback(model)
            #expect(result.verdict == .correct)
            #expect(result.correctAnswer == "shop — магазин")
            break
        }
        #expect(sawListening)
    }

    @Test func listeningNeverAppearsWithoutVoice() throws {
        for seed in UInt64(1)...30 {
            let (container, configuration) = try makeMatureSetup(direction: .enToRu)
            let model = makeModel(
                context: ModelContext(container),
                configuration: configuration,
                speech: MockSpeechService(isAvailable: false),
                seed: seed
            )
            model.start(now: t0)

            guard case .multipleChoice = try exercise(model).input else {
                throw TestAbort("expected multiple choice for seed \(seed), got \(model.phase)")
            }
        }
    }

    @Test func wordIsSpokenAutomaticallyAfterEachAnswer() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let speech = MockSpeechService(isAvailable: true)
        let model = makeModel(context: ModelContext(container), speech: speech)

        model.start(now: t0)
        #expect(model.canSpeakCurrentWord)
        model.speakCurrentWord()
        #expect(speech.spokenTexts == ["shop"])

        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(5))
        #expect(speech.spokenTexts == ["shop", "shop"])
    }

    @Test func speakingIsBlockedWhenTheWordIsTheAnswer() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let speech = MockSpeechService(isAvailable: true)
        let model = makeModel(context: ModelContext(container), speech: speech)

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(5))
        model.continueAfterFeedback(now: t0.addingTimeInterval(10))

        let exercise = try exercise(model)
        #expect(exercise.direction == .ruToEn)
        #expect(!model.canSpeakCurrentWord)
        let spokenBefore = speech.spokenTexts
        model.speakCurrentWord()
        #expect(speech.spokenTexts == spokenBefore)
    }

    @Test func contextExerciseMasksTheWordAndAcceptsIt() throws {
        var sawContext = false
        for seed in UInt64(1)...30 {
            let (container, configuration) = try makeMatureSetup(
                direction: .ruToEn,
                sentences: [
                    (en: "I bought bread at the shop.", ru: "Я купил хлеб в магазине."),
                    (en: "Two shops are closed.", ru: "Два магазина закрыты.")
                ]
            )
            let model = makeModel(
                context: ModelContext(container),
                configuration: configuration,
                seed: seed
            )
            model.start(now: t0)

            let exercise = try exercise(model)
            #expect(exercise.direction == .ruToEn)
            guard case .context(let translation) = exercise.input else { continue }
            sawContext = true

            // Only the sentence with the exact word form is usable.
            #expect(exercise.prompt == "I bought bread at the ____.")
            #expect(translation == "Я купил хлеб в магазине.")

            model.submitTypedAnswer("shop", now: t0.addingTimeInterval(5))
            #expect(try feedback(model).verdict == .correct)
            break
        }
        #expect(sawContext)
    }

    @Test func contextNeverAppearsWithoutAUsableSentence() throws {
        for seed in UInt64(1)...30 {
            let (container, configuration) = try makeMatureSetup(
                direction: .ruToEn,
                sentences: [(en: "Two shops are closed.", ru: "Два магазина закрыты.")]
            )
            let model = makeModel(
                context: ModelContext(container),
                configuration: configuration,
                seed: seed
            )
            model.start(now: t0)

            guard case .typedAnswer = try exercise(model).input else {
                throw TestAbort("expected typed answer for seed \(seed), got \(model.phase)")
            }
        }
    }

    @Test func leechGetsOneReintroductionWithHintBeforeItsFirstExercise() throws {
        let (container, configuration) = try makeMatureSetup(direction: .ruToEn)
        let setup = ModelContext(container)
        let shop = try #require(setup.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.wordId == 1 }
        )).first)
        shop.isLeech = true
        shop.leechHint = "Шоп — шоппинг происходит в магазине."
        try setup.save()

        let model = makeModel(context: ModelContext(container), configuration: configuration)
        model.start(now: t0)

        let card = try introCard(model)
        #expect(card.text == "shop")
        #expect(card.leechHint == "Шоп — шоппинг происходит в магазине.")

        model.completeIntroduction(now: t0)
        let first = try exercise(model)
        #expect(first.direction == .ruToEn)

        // A failed answer requeues the exercise — the re-introduction must not repeat.
        model.submitTypedAnswer("чепуха", now: t0.addingTimeInterval(5))
        model.continueAfterFeedback(now: t0.addingTimeInterval(10))
        let retried = try exercise(model)
        #expect(retried.direction == .ruToEn)
    }

    @Test func sessionSoftFinishesWhenDurationElapses() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        var configuration = SessionViewModel.Configuration()
        configuration.sessionDuration = 60
        let model = makeModel(context: ModelContext(container), configuration: configuration)

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(30))
        model.continueAfterFeedback(now: t0.addingTimeInterval(90))

        #expect(model.phase == .finished)
        let session = try #require(ModelContext(container).fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.endedAt == t0.addingTimeInterval(90))
        #expect(session.answersTotal == 1)
    }

    @Test func finishedSessionExposesSummaryWithStreak() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(5))
        model.endSession(now: t0.addingTimeInterval(10))

        let summary = try #require(model.summary)
        #expect(summary.wordsStudied == 1)
        #expect(summary.answersTotal == 1)
        #expect(summary.answersCorrect == 1)
        #expect(summary.accuracyPercent == 100)
        #expect(summary.newWordsIntroduced == 1)
        #expect(summary.streakDays == 1)
    }

    @Test func emptyQueueLeavesNoSummary() throws {
        let container = try makeContainer(importing: nil)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)

        #expect(model.phase == .finished)
        #expect(model.summary == nil)
    }

    @Test func endSessionEarlyKeepsRecordedAnswers() throws {
        let container = try makeContainer(importing: sixWordsJSON)
        let model = makeModel(context: ModelContext(container))

        model.start(now: t0)
        model.completeIntroduction(now: t0)
        model.submitChoice("магазин", now: t0.addingTimeInterval(5))
        model.endSession(now: t0.addingTimeInterval(10))

        #expect(model.phase == .finished)
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).count == 1)
        let session = try #require(context.fetch(FetchDescriptor<StudySession>()).first)
        #expect(session.endedAt == t0.addingTimeInterval(10))
    }
}

private struct TestAbort: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
