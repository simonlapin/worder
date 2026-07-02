import Foundation
import SwiftData

/// Flags words that keep being forgotten so they stop being ground endlessly
/// and surface in a dedicated list for special handling.
public struct LeechDetector: Sendable {
    public let lapseThreshold: Int

    public init(lapseThreshold: Int = 6) {
        precondition(lapseThreshold > 0, "lapseThreshold must be positive")
        self.lapseThreshold = lapseThreshold
    }

    /// A word is a leech when any direction reached the lapse threshold.
    public func isLeech(_ word: Word) -> Bool {
        word.directionStates.contains { $0.lapses >= lapseThreshold }
    }

    /// Re-evaluates and persists the flag; call after recording an answer.
    @discardableResult
    public func updateFlag(for word: Word) -> Bool {
        word.isLeech = isLeech(word)
        return word.isLeech
    }

    public func leeches(in context: ModelContext) throws -> [Word] {
        try context.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { $0.isLeech },
            sortBy: [SortDescriptor(\.wordId)]
        ))
    }
}
