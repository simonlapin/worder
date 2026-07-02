import Foundation
import SwiftData

public struct BatchImportSummary: Equatable, Sendable {
    public let batchId: String
    public let insertedWords: Int
    public let updatedWords: Int
    public let unchangedWords: Int
}

/// Imports word batches idempotently. Words are keyed by `(batchId, wordId)`:
/// re-importing updates vocabulary content but never touches learning state
/// (`DirectionState`) or review history. Words absent from a newer file are
/// kept — removing them would silently destroy progress.
public struct BatchImporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func importBatch(from data: Data, now: Date) throws -> BatchImportSummary {
        try importBatch(WordBatchFile.decode(from: data), now: now)
    }

    @discardableResult
    public func importBatch(_ file: WordBatchFile, now: Date) throws -> BatchImportSummary {
        try file.validate()

        let batch = try fetchOrCreateBatch(for: file, now: now)
        var wordsById = Dictionary(uniqueKeysWithValues: batch.words.map { ($0.wordId, $0) })

        var inserted = 0
        var updated = 0
        var unchanged = 0

        for entry in file.words {
            if let existing = wordsById[entry.id] {
                if update(existing, from: entry) {
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let word = insertWord(from: entry, into: batch, now: now)
                wordsById[entry.id] = word
                inserted += 1
            }
        }

        try context.save()
        return BatchImportSummary(
            batchId: file.batchId,
            insertedWords: inserted,
            updatedWords: updated,
            unchangedWords: unchanged
        )
    }

    private func fetchOrCreateBatch(for file: WordBatchFile, now: Date) throws -> Batch {
        let batchId = file.batchId
        let descriptor = FetchDescriptor<Batch>(predicate: #Predicate { $0.batchId == batchId })
        if let existing = try context.fetch(descriptor).first {
            existing.title = file.title
            existing.category = file.category
            existing.schemaVersion = file.schemaVersion
            return existing
        }
        let batch = Batch(
            batchId: file.batchId,
            title: file.title,
            category: file.category,
            schemaVersion: file.schemaVersion,
            importedAt: now
        )
        context.insert(batch)
        return batch
    }

    private func insertWord(from entry: WordBatchFile.Entry, into batch: Batch, now: Date) -> Word {
        let word = Word(
            wordId: entry.id,
            text: entry.word,
            translations: entry.translations,
            note: entry.note,
            category: entry.category
        )
        context.insert(word)
        word.batch = batch
        for direction in Direction.allCases {
            let state = DirectionState(direction: direction, due: now)
            context.insert(state)
            state.word = word
        }
        return word
    }

    /// Applies vocabulary fields from the entry; returns true if anything changed.
    private func update(_ word: Word, from entry: WordBatchFile.Entry) -> Bool {
        var changed = false
        if word.text != entry.word {
            word.text = entry.word
            changed = true
        }
        if word.translations != entry.translations {
            word.translations = entry.translations
            changed = true
        }
        if word.note != entry.note {
            word.note = entry.note
            changed = true
        }
        if word.category != entry.category {
            word.category = entry.category
            changed = true
        }
        return changed
    }
}
