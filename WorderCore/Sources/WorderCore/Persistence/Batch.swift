import Foundation
import SwiftData

/// An imported word batch. Words are keyed by `(batchId, wordId)` for idempotent re-import.
@Model
public final class Batch {
    public var batchId: String
    public var title: String
    public var category: String?
    public var schemaVersion: Int
    public var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Word.batch)
    public var words: [Word]

    public init(
        batchId: String,
        title: String,
        category: String? = nil,
        schemaVersion: Int,
        importedAt: Date
    ) {
        self.batchId = batchId
        self.title = title
        self.category = category
        self.schemaVersion = schemaVersion
        self.importedAt = importedAt
        self.words = []
    }
}
