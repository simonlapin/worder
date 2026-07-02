import Foundation
import SwiftData

/// Restores a `StateBackup` into an EMPTY database. Overwrite protection is
/// the caller's job: it must confirm with the user and call `eraseAll` first.
public struct StateImporter: Sendable {
    public enum ImportError: Error, Equatable, LocalizedError {
        case unsupportedVersion(Int)
        case databaseNotEmpty
        case invalidBackup(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "Backup version \(version) is not supported (expected \(StateBackup.currentVersion))."
            case .databaseNotEmpty:
                "The database is not empty; erase it before restoring a backup."
            case .invalidBackup(let details):
                "The backup file is invalid: \(details)."
            }
        }
    }

    public init() {}

    public func decode(_ data: Data) throws -> StateBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let backup: StateBackup
        do {
            backup = try decoder.decode(StateBackup.self, from: data)
        } catch {
            throw ImportError.invalidBackup(String(describing: error))
        }
        guard backup.backupVersion == StateBackup.currentVersion else {
            throw ImportError.unsupportedVersion(backup.backupVersion)
        }
        return backup
    }

    /// Restores the backup and saves. Throws `databaseNotEmpty` when any
    /// domain entity already exists.
    @discardableResult
    public func importState(_ data: Data, into context: ModelContext) throws -> StateBackup {
        let backup = try decode(data)

        guard try isDatabaseEmpty(context) else {
            throw ImportError.databaseNotEmpty
        }

        for batchBackup in backup.batches {
            let batch = Batch(
                batchId: batchBackup.batchId,
                title: batchBackup.title,
                category: batchBackup.category,
                schemaVersion: batchBackup.schemaVersion,
                importedAt: batchBackup.importedAt
            )
            context.insert(batch)
            for wordBackup in batchBackup.words {
                restoreWord(wordBackup, batch: batch, in: context)
            }
        }
        for wordBackup in backup.unbatchedWords {
            restoreWord(wordBackup, batch: nil, in: context)
        }
        for sessionBackup in backup.sessions {
            context.insert(StudySession(
                startedAt: sessionBackup.startedAt,
                endedAt: sessionBackup.endedAt,
                answersTotal: sessionBackup.answersTotal,
                answersCorrect: sessionBackup.answersCorrect,
                newWordsIntroduced: sessionBackup.newWordsIntroduced
            ))
        }

        try context.save()
        return backup
    }

    /// Deletes every domain entity. Cascade rules on `Batch` and `Word` take
    /// care of dependents; orphans are removed explicitly.
    public func eraseAll(in context: ModelContext) throws {
        for batch in try context.fetch(FetchDescriptor<Batch>()) {
            context.delete(batch)
        }
        for word in try context.fetch(FetchDescriptor<Word>()) {
            context.delete(word)
        }
        for session in try context.fetch(FetchDescriptor<StudySession>()) {
            context.delete(session)
        }
        for state in try context.fetch(FetchDescriptor<DirectionState>()) {
            context.delete(state)
        }
        for log in try context.fetch(FetchDescriptor<ReviewLog>()) {
            context.delete(log)
        }
        for sentence in try context.fetch(FetchDescriptor<CachedSentence>()) {
            context.delete(sentence)
        }
        try context.save()
    }

    public func isDatabaseEmpty(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<Word>()) == 0
            && context.fetchCount(FetchDescriptor<Batch>()) == 0
            && context.fetchCount(FetchDescriptor<StudySession>()) == 0
    }

    private func restoreWord(_ wordBackup: StateBackup.WordBackup, batch: Batch?, in context: ModelContext) {
        let word = Word(
            wordId: wordBackup.wordId,
            text: wordBackup.text,
            translations: wordBackup.translations,
            note: wordBackup.note,
            category: wordBackup.category,
            isLeech: wordBackup.isLeech,
            leechHint: wordBackup.leechHint
        )
        context.insert(word)
        word.batch = batch

        for stateBackup in wordBackup.directionStates {
            let state = DirectionState(
                direction: stateBackup.direction,
                state: stateBackup.state,
                stability: stateBackup.stability,
                difficulty: stateBackup.difficulty,
                due: stateBackup.due,
                lapses: stateBackup.lapses,
                reps: stateBackup.reps,
                lastReviewedAt: stateBackup.lastReviewedAt
            )
            context.insert(state)
            state.word = word
        }
        for logBackup in wordBackup.reviewLogs {
            let log = ReviewLog(
                reviewedAt: logBackup.reviewedAt,
                direction: logBackup.direction,
                grade: logBackup.grade
            )
            context.insert(log)
            log.word = word
        }
        for sentenceBackup in wordBackup.sentences {
            let sentence = CachedSentence(
                en: sentenceBackup.en,
                ru: sentenceBackup.ru,
                createdAt: sentenceBackup.createdAt
            )
            context.insert(sentence)
            sentence.word = word
        }
    }
}
