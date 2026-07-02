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
        var sessionDuration: TimeInterval = 30 * 60
        var queue = SessionQueue.Configuration()
        var selector = ExerciseSelector.Configuration()
        var checker = AnswerChecker.Configuration()
        var distractors = DistractorGenerator.Configuration()
        var leechLapseThreshold = 6
    }

    struct IntroCard: Equatable {
        let text: String
        let translations: [String]
        let note: String?
    }

    struct Exercise: Equatable {
        enum Input: Equatable {
            case multipleChoice(options: [String])
            case typedAnswer
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

    private let context: ModelContext
    private let configuration: Configuration
    private let scheduler: any Scheduler
    private let calendar: Calendar
    private var rng: AnyRandomNumberGenerator

    private var queue: SessionQueue?
    private var checker: AnswerChecker?
    private var candidates: [DistractorCandidate] = []
    private var currentItem: SessionItem?
    private var currentCorrectOption: String?
    private var sessionStartedAt: Date?

    private(set) var phase: Phase = .loading
    private(set) var sessionRecord: StudySession?
    private(set) var completedCount = 0

    var progressFraction: Double {
        let total = completedCount + (queue?.remainingCount ?? 0)
        guard total > 0 else { return 1 }
        return Double(completedCount) / Double(total)
    }

    init(
        context: ModelContext,
        configuration: Configuration = Configuration(),
        scheduler: any Scheduler = FSRSScheduler(),
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        calendar: Calendar = .current
    ) {
        self.context = context
        self.configuration = configuration
        self.scheduler = scheduler
        self.calendar = calendar
        self.rng = AnyRandomNumberGenerator(rng)
    }

    func start(now: Date = .now) {
        guard case .loading = phase else { return }
        do {
            let queue = try SessionQueue(
                context: context,
                configuration: configuration.queue,
                calendar: calendar,
                now: now
            )
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
            let record = StudySession(startedAt: now)
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
        queue.markCompleted(item, now: now)
        completedCount += 1
        advance(now: now)
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
        if let startedAt = sessionStartedAt,
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
        switch item.kind {
        case .introduction:
            phase = .introduction(IntroCard(
                text: item.word.text,
                translations: item.word.translations,
                note: item.word.note
            ))
        case .exercise(let direction):
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

        let capabilities = ExerciseSelector.Capabilities(
            hasCachedSentences: !word.sentences.isEmpty,
            canPlayAudio: false
        )
        let type = ExerciseSelector(configuration: configuration.selector).exerciseType(
            for: state.schedulerCard,
            direction: direction,
            capabilities: capabilities,
            using: &rng
        )

        switch type {
        case .multipleChoice, .listening:
            presentMultipleChoice(word: word, direction: direction)
        case .typedAnswer, .context:
            presentTypedAnswer(word: word, direction: direction)
        }
    }

    private func presentMultipleChoice(word: Word, direction: Direction) {
        guard let correctOption = correctOption(word: word, direction: direction) else {
            phase = .failed("Word \"\(word.text)\" has no translations.")
            return
        }
        do {
            let distractors = try DistractorGenerator(configuration: configuration.distractors)
                .distractors(
                    for: DistractorCandidate(word: word),
                    direction: direction,
                    candidates: candidates,
                    using: &rng
                )
            currentCorrectOption = correctOption
            phase = .exercise(Exercise(
                direction: direction,
                prompt: prompt(word: word, direction: direction),
                note: direction == .enToRu ? word.note : nil,
                input: .multipleChoice(options: (distractors + [correctOption]).shuffled(using: &rng))
            ))
        } catch {
            // Too few disjoint candidates (tiny dictionaries): typing still works.
            presentTypedAnswer(word: word, direction: direction)
        }
    }

    private func presentTypedAnswer(word: Word, direction: Direction) {
        phase = .exercise(Exercise(
            direction: direction,
            prompt: prompt(word: word, direction: direction),
            note: direction == .enToRu ? word.note : nil,
            input: .typedAnswer
        ))
    }

    private func record(verdict: AnswerVerdict, now: Date) {
        guard let item = currentItem,
              case .exercise(let direction) = item.kind,
              let queue,
              let sessionRecord else { return }
        let word = item.word
        let grade = verdict.reviewGrade

        do {
            guard let state = word.directionState(for: direction) else {
                phase = .failed("Word \"\(word.text)\" is missing state for \(direction.rawValue).")
                return
            }
            let nextCard = try scheduler.next(card: state.schedulerCard, grade: grade, now: now)
            let isFirstAnswerEver = word.reviewLogs.isEmpty

            let log = ReviewLog(reviewedAt: now, direction: direction, grade: grade)
            context.insert(log)
            log.word = word
            state.apply(nextCard)
            LeechDetector(lapseThreshold: configuration.leechLapseThreshold).updateFlag(for: word)

            sessionRecord.answersTotal += 1
            if grade != .again {
                sessionRecord.answersCorrect += 1
            }
            if isFirstAnswerEver {
                sessionRecord.newWordsIntroduced += 1
            }
            try context.save()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let willRetry = grade == .again
        if willRetry {
            queue.markFailed(item, now: now)
        } else {
            queue.markCompleted(item, now: now)
            completedCount += 1
        }
        phase = .feedback(Feedback(
            verdict: verdict,
            correctAnswer: correctAnswerText(word: word, direction: direction),
            willRetry: willRetry
        ))
    }

    private func finish(now: Date) {
        if let sessionRecord, sessionRecord.endedAt == nil {
            sessionRecord.endedAt = now
            do {
                try context.save()
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
