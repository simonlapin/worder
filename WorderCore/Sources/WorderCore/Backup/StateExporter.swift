import Foundation
import SwiftData

/// Serializes the whole database plus user settings into one JSON document.
/// Output is deterministic (sorted keys, stable entity ordering) so identical
/// states produce identical files.
public struct StateExporter: Sendable {
    public init() {}

    public func export(
        from context: ModelContext,
        settings: StateBackup.Settings,
        now: Date
    ) throws -> Data {
        let backup = try snapshot(from: context, settings: settings, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public func snapshot(
        from context: ModelContext,
        settings: StateBackup.Settings,
        now: Date
    ) throws -> StateBackup {
        let batches = try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.batchId)]
        ))
        let allWords = try context.fetch(FetchDescriptor<Word>(
            sortBy: [SortDescriptor(\.wordId)]
        ))
        let sessions = try context.fetch(FetchDescriptor<StudySession>(
            sortBy: [SortDescriptor(\.startedAt)]
        ))

        return StateBackup(
            exportedAt: now,
            settings: settings,
            batches: batches.map { batch in
                StateBackup.BatchBackup(
                    batchId: batch.batchId,
                    title: batch.title,
                    category: batch.category,
                    schemaVersion: batch.schemaVersion,
                    importedAt: batch.importedAt,
                    words: batch.words
                        .sorted { $0.wordId < $1.wordId }
                        .map(backupWord)
                )
            },
            unbatchedWords: allWords.filter { $0.batch == nil }.map(backupWord),
            sessions: sessions.map { session in
                StateBackup.SessionBackup(
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    answersTotal: session.answersTotal,
                    answersCorrect: session.answersCorrect,
                    newWordsIntroduced: session.newWordsIntroduced,
                    mode: session.mode
                )
            }
        )
    }

    private func backupWord(_ word: Word) -> StateBackup.WordBackup {
        StateBackup.WordBackup(
            wordId: word.wordId,
            text: word.text,
            translations: word.translations,
            note: word.note,
            category: word.category,
            isLeech: word.isLeech,
            leechHint: word.leechHint,
            directionStates: word.directionStates
                .sorted { $0.directionRaw < $1.directionRaw }
                .map { state in
                    StateBackup.DirectionStateBackup(
                        direction: state.direction,
                        state: state.state,
                        stability: state.stability,
                        difficulty: state.difficulty,
                        due: state.due,
                        lapses: state.lapses,
                        reps: state.reps,
                        lastReviewedAt: state.lastReviewedAt
                    )
                },
            reviewLogs: word.reviewLogs
                .sorted { $0.reviewedAt < $1.reviewedAt }
                .map { log in
                    StateBackup.ReviewLogBackup(
                        reviewedAt: log.reviewedAt,
                        direction: log.direction,
                        grade: log.grade,
                        isFreePractice: log.isFreePractice
                    )
                },
            sentences: word.sentences
                .sorted { $0.createdAt < $1.createdAt }
                .map { sentence in
                    StateBackup.SentenceBackup(
                        en: sentence.en,
                        ru: sentence.ru,
                        createdAt: sentence.createdAt
                    )
                }
        )
    }
}
