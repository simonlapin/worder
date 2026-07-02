import Foundation
import Observation
import SwiftData
import WorderCore

struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}

/// Drives one study session: pulls work from `SessionQueue`, presents
/// exercises, grades answers, and persists every result immediately so
/// quitting at any moment loses nothing.
@MainActor
@Observable
final class SessionViewModel {
    struct Configuration {
        /// Free practice never moves the FSRS schedule and has no soft timer.
        var mode: StudySessionMode = .scheduled
        var sessionDuration: TimeInterval = 30 * 60
        var queue = SessionQueue.Configuration()
        var freeQueue = FreePracticeQueue.Configuration()
        var selector = ExerciseSelector.Configuration()
        var checker = AnswerChecker.Configuration()
        var distractors = DistractorGenerator.Configuration()
        var leechLapseThreshold = 6
    }

    struct IntroCard: Equatable {
        let text: String
        let translations: [String]
        let note: String?
        /// Cached leech help; present only on the re-introduction card
        /// a leech gets before its first exercise of the session.
        var leechHint: String?
    }

    struct Exercise: Equatable {
        enum Input: Equatable {
            case multipleChoice(options: [String])
            case typedAnswer
            /// The word is spoken, not shown; options are translations.
            case listening(options: [String])
            /// The prompt is a sentence with the word masked out;
            /// `translation` is its Russian counterpart shown as a hint.
            case context(translation: String)
        }

        let direction: Direction
        let prompt: String
        let note: String?
        let input: Input
    }

    struct Feedback: Equatable {
        let verdict: AnswerVerdict
        let correctAnswer: String
        /// Failed items re-enter the queue of this same session.
        let willRetry: Bool
    }

    enum Phase: Equatable {
        case loading
        case introduction(IntroCard)
        case exercise(Exercise)
        case feedback(Feedback)
        case finished
        case failed(String)
    }

    struct Summary: Equatable {
        let wordsStudied: Int
        let answersTotal: Int
        let answersCorrect: Int
        let newWordsIntroduced: Int
        let streakDays: Int

        var accuracyPercent: Int {
            guard answersTotal > 0 else { return 0 }
            return Int((Double(answersCorrect) / Double(answersTotal) * 100).rounded())
        }
    }

    private let context: ModelContext
    private let configuration: Configuration
    private let scheduler: any Scheduler
    private let speech: any SpeechService
    private let calendar: Calendar
    private var rng: AnyRandomNumberGenerator

    private var queue: (any SessionWorkQueue)?
    private var checker: AnswerChecker?
    private var candidates: [DistractorCandidate] = []
    private var currentItem: SessionItem?
    private var currentCorrectOption: String?
    private var sessionStartedAt: Date?
    private var studiedWordIds: Set<PersistentIdentifier> = []
    private var leechIntrosShown: Set<PersistentIdentifier> = []

    private(set) var phase: Phase = .loading
    private(set) var sessionRecord: StudySession?
    private(set) var summary: Summary?
    private(set) var completedCount = 0
    /// Mastery status of the word on screen; free practice only, so the
    /// trainee sees what kind of word they are dealing with.
    private(set) var currentWordStatus: WordStatus?
    private(set) var currentWordIsLeech = false

    var progressFraction: Double {
        let total = completedCount + (queue?.remainingCount ?? 0)
        guard total > 0 else { return 1 }
        return Double(completedCount) / Double(total)
    }

    init(
        context: ModelContext,
        configuration: Configuration = Configuration(),
        scheduler: any Scheduler = FSRSScheduler(),
        speech: any SpeechService = SystemSpeechService(),
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        calendar: Calendar = .current
    ) {
        self.context = context
        self.configuration = configuration
        self.scheduler = scheduler
        self.speech = speech
        self.calendar = calendar
        self.rng = AnyRandomNumberGenerator(rng)
    }

    func start(now: Date = .now) {
        guard case .loading = phase else { return }
        do {
            let queue: any SessionWorkQueue = switch configuration.mode {
            case .scheduled:
                try SessionQueue(
                    context: context,
                    configuration: configuration.queue,
                    calendar: calendar,
                    now: now
                )
            case .free:
                try FreePracticeQueue(
                    context: context,
                    configuration: configuration.freeQueue,
                    now: now,
                    using: &rng
                )
            }
            self.queue = queue
            checker = AnswerChecker(
                index: try TranslationIndex(context: context),
                configuration: configuration.checker
            )
            candidates = try context.fetch(FetchDescriptor<Word>()).map(DistractorCandidate.init)

            guard !queue.isEmpty else {
                phase = .finished
                return
            }
            let record = StudySession(startedAt: now, mode: configuration.mode)
            context.insert(record)
            try context.save()
            sessionRecord = record
            sessionStartedAt = now
            advance(now: now)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func completeIntroduction(now: Date = .now) {
        guard case .introduction = phase, let item = currentItem, let queue else { return }
        switch item.kind {
        case .introduction:
            queue.markCompleted(item, now: now)
            completedCount += 1
            advance(now: now)
        case .exercise(let direction):
            // Leech re-introduction shown on top of an exercise item:
            // the queue item is untouched, proceed to the exercise itself.
            presentExercise(item: item, direction: direction, now: now)
        }
    }

    func submitChoice(_ option: String, now: Date = .now) {
        guard case .exercise = phase, let correct = currentCorrectOption else { return }
        record(verdict: option == correct ? .correct : .wrong, now: now)
    }

    func submitTypedAnswer(_ input: String, now: Date = .now) {
        guard case .exercise(let exercise) = phase, let item = currentItem, let checker else { return }
        let verdict = checker.check(
            input,
            direction: exercise.direction,
            wordText: item.word.text,
            translations: item.word.translations
        )
        record(verdict: verdict, now: now)
    }

    func continueAfterFeedback(now: Date = .now) {
        guard case .feedback = phase else { return }
        advance(now: now)
    }

    func endSession(now: Date = .now) {
        switch phase {
        case .finished, .failed, .loading:
            return
        case .introduction, .exercise, .feedback:
            finish(now: now)
        }
    }

    private func advance(now: Date) {
        guard let queue else { return }
        guard !queue.isEmpty else {
            finish(now: now)
            return
        }
        if configuration.mode == .scheduled,
           let startedAt = sessionStartedAt,
           now.timeIntervalSince(startedAt) >= configuration.sessionDuration {
            finish(now: now)
            return
        }
        guard let item = queue.nextItem(now: now) else {
            finish(now: now)
            return
        }
        currentItem = item
        currentCorrectOption = nil
        if configuration.mode == .free {
            currentWordStatus = MasteryPolicy().status(of: item.word, now: now)
            currentWordIsLeech = item.word.isLeech
        }
        switch item.kind {
        case .introduction:
            phase = .introduction(IntroCard(
                text: item.word.text,
                translations: item.word.translations,
                note: item.word.note
            ))
        case .exercise(let direction):
            if let hint = item.word.leechHint, item.word.isLeech,
               leechIntrosShown.insert(item.word.persistentModelID).inserted {
                // A leech gets one re-introduction with its hint per session
                // before the first exercise on it.
                phase = .introduction(IntroCard(
                    text: item.word.text,
                    translations: item.word.translations,
                    note: item.word.note,
                    leechHint: hint
                ))
                return
            }
            presentExercise(item: item, direction: direction, now: now)
        }
    }

    private func presentExercise(item: SessionItem, direction: Direction, now: Date) {
        let word = item.word
        guard let state = word.directionState(for: direction) else {
            // Data anomaly (importer always creates both directions):
            // drop the item instead of killing the whole session.
            queue?.markCompleted(item, now: now)
            completedCount += 1
            advance(now: now)
            return
        }

        let sentences = word.sentences.map { WordBatchFile.Sentence(en: $0.en, ru: $0.ru) }
        let capabilities = ExerciseSelector.Capabilities(
            hasCachedSentences: ContextSentencePicker()
                .hasUsableSentence(wordText: word.text, sentences: sentences),
            canPlayAudio: speech.isAvailable
        )
        let type = ExerciseSelector(configuration: configuration.selector).exerciseType(
            for: state.schedulerCard,
            direction: direction,
            capabilities: capabilities,
            using: &rng
        )

        switch type {
        case .multipleChoice:
            presentMultipleChoice(word: word, direction: direction)
        case .listening:
            presentListening(word: word)
        case .context:
            presentContext(word: word, sentences: sentences)
        case .typedAnswer:
            presentTypedAnswer(word: word, direction: direction)
        }
    }

    private func presentContext(word: Word, sentences: [WordBatchFile.Sentence]) {
        guard let picked = ContextSentencePicker()
            .pick(wordText: word.text, sentences: sentences, using: &rng) else {
            presentTypedAnswer(word: word, direction: .ruToEn)
            return
        }
        phase = .exercise(Exercise(
            direction: .ruToEn,
            prompt: picked.masked,
            note: nil,
            input: .context(translation: picked.translation)
        ))
    }

    private func presentMultipleChoice(word: Word, direction: Direction) {
        do {
            guard let (correctOption, options) = try makeChoiceOptions(word: word, direction: direction) else {
                phase = .failed("Word \"\(word.text)\" has no translations.")
                return
            }
            currentCorrectOption = correctOption
            phase = .exercise(Exercise(
                direction: direction,
                prompt: prompt(word: word, direction: direction),
                note: direction == .enToRu ? word.note : nil,
                input: .multipleChoice(options: options)
            ))
        } catch {
            // Too few disjoint candidates (tiny dictionaries): typing still works.
            presentTypedAnswer(word: word, direction: direction)
        }
    }

    private func presentListening(word: Word) {
        do {
            guard let (correctOption, options) = try makeChoiceOptions(word: word, direction: .enToRu) else {
                phase = .failed("Word \"\(word.text)\" has no translations.")
                return
            }
            currentCorrectOption = correctOption
            phase = .exercise(Exercise(
                direction: .enToRu,
                prompt: "",
                note: nil,
                input: .listening(options: options)
            ))
            speech.speak(word.text)
        } catch {
            presentMultipleChoice(word: word, direction: .enToRu)
        }
    }

    private func makeChoiceOptions(word: Word, direction: Direction) throws -> (correct: String, options: [String])? {
        guard let correctOption = correctOption(word: word, direction: direction) else { return nil }
        let distractors = try DistractorGenerator(configuration: configuration.distractors)
            .distractors(
                for: DistractorCandidate(word: word),
                direction: direction,
                candidates: candidates,
                using: &rng
            )
        return (correctOption, (distractors + [correctOption]).shuffled(using: &rng))
    }

    private func presentTypedAnswer(word: Word, direction: Direction) {
        phase = .exercise(Exercise(
            direction: direction,
            prompt: prompt(word: word, direction: direction),
            note: direction == .enToRu ? word.note : nil,
            input: .typedAnswer
        ))
    }

    /// The audible word for the current phase; nil when speaking it would
    /// give the answer away (RU→EN exercises) or no voice is available.
    private var speakableWordText: String? {
        guard speech.isAvailable, let item = currentItem else { return nil }
        switch phase {
        case .introduction, .feedback:
            return item.word.text
        case .exercise(let exercise):
            return exercise.direction == .enToRu ? item.word.text : nil
        case .loading, .finished, .failed:
            return nil
        }
    }

    var canSpeakCurrentWord: Bool { speakableWordText != nil }

    func speakCurrentWord() {
        guard let text = speakableWordText else { return }
        speech.speak(text)
    }

    private func record(verdict: AnswerVerdict, now: Date) {
        guard let item = currentItem,
              case .exercise(let direction) = item.kind,
              let queue,
              let sessionRecord else { return }
        let word = item.word
        let grade = verdict.reviewGrade

        do {
            switch configuration.mode {
            case .scheduled:
                guard let state = word.directionState(for: direction) else {
                    phase = .failed("Word \"\(word.text)\" is missing state for \(direction.rawValue).")
                    return
                }
                let nextCard = try scheduler.next(card: state.schedulerCard, grade: grade, now: now)
                // Free practice answers never introduce a word into the schedule.
                let isFirstScheduledAnswer = word.reviewLogs.allSatisfy(\.isFreePractice)

                let log = ReviewLog(reviewedAt: now, direction: direction, grade: grade)
                context.insert(log)
                log.word = word
                state.apply(nextCard)
                LeechDetector(lapseThreshold: configuration.leechLapseThreshold).updateFlag(for: word)
                if isFirstScheduledAnswer {
                    sessionRecord.newWordsIntroduced += 1
                }
            case .free:
                // Trainer only: log the answer for history and honest mastery
                // status, leave DirectionState and the FSRS schedule untouched.
                let log = ReviewLog(reviewedAt: now, direction: direction, grade: grade, isFreePractice: true)
                context.insert(log)
                log.word = word
            }

            sessionRecord.answersTotal += 1
            if grade != .again {
                sessionRecord.answersCorrect += 1
            }
            studiedWordIds.insert(word.persistentModelID)
            try context.save()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let wasListening = if case .exercise(let exercise) = phase,
                              case .listening = exercise.input { true } else { false }

        let willRetry = grade == .again
        if willRetry {
            queue.markFailed(item, now: now)
        } else {
            queue.markCompleted(item, now: now)
            completedCount += 1
        }
        phase = .feedback(Feedback(
            verdict: verdict,
            // After a listening exercise the word was never shown — include it.
            correctAnswer: wasListening
                ? "\(word.text) — \(correctAnswerText(word: word, direction: direction))"
                : correctAnswerText(word: word, direction: direction),
            willRetry: willRetry
        ))
        speech.speak(word.text)
    }

    private func finish(now: Date) {
        speech.stop()
        if let sessionRecord {
            do {
                if sessionRecord.endedAt == nil {
                    sessionRecord.endedAt = now
                    try context.save()
                }
                summary = Summary(
                    wordsStudied: studiedWordIds.count,
                    answersTotal: sessionRecord.answersTotal,
                    answersCorrect: sessionRecord.answersCorrect,
                    newWordsIntroduced: sessionRecord.newWordsIntroduced,
                    streakDays: try StreakCalculator(calendar: calendar)
                        .currentStreak(in: context, now: now)
                )
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        phase = .finished
    }

    private func prompt(word: Word, direction: Direction) -> String {
        switch direction {
        case .enToRu: word.text
        case .ruToEn: word.translations.joined(separator: ", ")
        }
    }

    private func correctOption(word: Word, direction: Direction) -> String? {
        switch direction {
        case .enToRu: word.translations.first
        case .ruToEn: word.text
        }
    }

    private func correctAnswerText(word: Word, direction: Direction) -> String {
        switch direction {
        case .enToRu: word.translations.joined(separator: ", ")
        case .ruToEn: word.text
        }
    }
}
