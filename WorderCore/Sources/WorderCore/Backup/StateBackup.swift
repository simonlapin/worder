import Foundation

/// Full-state backup document: every batch, word, per-direction card state,
/// review log, cached sentence, study session, and user settings.
/// The Anthropic API key is deliberately NOT part of a backup.
public struct StateBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct Settings: Codable, Equatable, Sendable {
        /// nil = no daily limit on new words.
        public var dailyNewWordLimit: Int?
        public var remindersEnabled: Bool
        /// Minutes since midnight.
        public var reminderTimes: [Int]

        public init(dailyNewWordLimit: Int?, remindersEnabled: Bool, reminderTimes: [Int]) {
            self.dailyNewWordLimit = dailyNewWordLimit
            self.remindersEnabled = remindersEnabled
            self.reminderTimes = reminderTimes
        }
    }

    public struct BatchBackup: Codable, Equatable, Sendable {
        public var batchId: String
        public var title: String
        public var category: String?
        public var schemaVersion: Int
        public var importedAt: Date
        public var words: [WordBackup]

        public init(
            batchId: String,
            title: String,
            category: String?,
            schemaVersion: Int,
            importedAt: Date,
            words: [WordBackup]
        ) {
            self.batchId = batchId
            self.title = title
            self.category = category
            self.schemaVersion = schemaVersion
            self.importedAt = importedAt
            self.words = words
        }
    }

    public struct WordBackup: Codable, Equatable, Sendable {
        public var wordId: Int
        public var text: String
        public var translations: [String]
        public var note: String?
        public var category: String?
        public var isLeech: Bool
        public var leechHint: String?
        public var directionStates: [DirectionStateBackup]
        public var reviewLogs: [ReviewLogBackup]
        public var sentences: [SentenceBackup]

        public init(
            wordId: Int,
            text: String,
            translations: [String],
            note: String?,
            category: String?,
            isLeech: Bool,
            leechHint: String?,
            directionStates: [DirectionStateBackup],
            reviewLogs: [ReviewLogBackup],
            sentences: [SentenceBackup]
        ) {
            self.wordId = wordId
            self.text = text
            self.translations = translations
            self.note = note
            self.category = category
            self.isLeech = isLeech
            self.leechHint = leechHint
            self.directionStates = directionStates
            self.reviewLogs = reviewLogs
            self.sentences = sentences
        }
    }

    public struct DirectionStateBackup: Codable, Equatable, Sendable {
        public var direction: Direction
        public var state: CardState
        public var stability: Double
        public var difficulty: Double
        public var due: Date
        public var lapses: Int
        public var reps: Int
        public var lastReviewedAt: Date?

        public init(
            direction: Direction,
            state: CardState,
            stability: Double,
            difficulty: Double,
            due: Date,
            lapses: Int,
            reps: Int,
            lastReviewedAt: Date?
        ) {
            self.direction = direction
            self.state = state
            self.stability = stability
            self.difficulty = difficulty
            self.due = due
            self.lapses = lapses
            self.reps = reps
            self.lastReviewedAt = lastReviewedAt
        }
    }

    public struct ReviewLogBackup: Codable, Equatable, Sendable {
        public var reviewedAt: Date
        public var direction: Direction
        public var grade: ReviewGrade

        public init(reviewedAt: Date, direction: Direction, grade: ReviewGrade) {
            self.reviewedAt = reviewedAt
            self.direction = direction
            self.grade = grade
        }
    }

    public struct SentenceBackup: Codable, Equatable, Sendable {
        public var en: String
        public var ru: String
        public var createdAt: Date

        public init(en: String, ru: String, createdAt: Date) {
            self.en = en
            self.ru = ru
            self.createdAt = createdAt
        }
    }

    public struct SessionBackup: Codable, Equatable, Sendable {
        public var startedAt: Date
        public var endedAt: Date?
        public var answersTotal: Int
        public var answersCorrect: Int
        public var newWordsIntroduced: Int

        public init(
            startedAt: Date,
            endedAt: Date?,
            answersTotal: Int,
            answersCorrect: Int,
            newWordsIntroduced: Int
        ) {
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.answersTotal = answersTotal
            self.answersCorrect = answersCorrect
            self.newWordsIntroduced = newWordsIntroduced
        }
    }

    public var backupVersion: Int
    public var exportedAt: Date
    public var settings: Settings
    public var batches: [BatchBackup]
    /// Words that exist outside any batch (not produced by normal imports,
    /// but the model allows them — a backup must be lossless).
    public var unbatchedWords: [WordBackup]
    public var sessions: [SessionBackup]

    public init(
        backupVersion: Int = StateBackup.currentVersion,
        exportedAt: Date,
        settings: Settings,
        batches: [BatchBackup],
        unbatchedWords: [WordBackup],
        sessions: [SessionBackup]
    ) {
        self.backupVersion = backupVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.batches = batches
        self.unbatchedWords = unbatchedWords
        self.sessions = sessions
    }
}
