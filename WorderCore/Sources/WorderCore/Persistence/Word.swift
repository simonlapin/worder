import Foundation
import SwiftData

/// A single vocabulary entry with its per-direction learning state.
@Model
public final class Word {
    /// Entry id within its batch (`WordBatchFile.Entry.id`).
    public var wordId: Int
    public var text: String
    public var translations: [String]
    public var note: String?
    public var category: String?
    public var isLeech: Bool

    public var batch: Batch?

    @Relationship(deleteRule: .cascade, inverse: \DirectionState.word)
    public var directionStates: [DirectionState]

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)
    public var reviewLogs: [ReviewLog]

    @Relationship(deleteRule: .cascade, inverse: \CachedSentence.word)
    public var sentences: [CachedSentence]

    public init(
        wordId: Int,
        text: String,
        translations: [String],
        note: String? = nil,
        category: String? = nil,
        isLeech: Bool = false
    ) {
        self.wordId = wordId
        self.text = text
        self.translations = translations
        self.note = note
        self.category = category
        self.isLeech = isLeech
        self.directionStates = []
        self.reviewLogs = []
        self.sentences = []
    }

    public func directionState(for direction: Direction) -> DirectionState? {
        directionStates.first { $0.direction == direction }
    }
}
