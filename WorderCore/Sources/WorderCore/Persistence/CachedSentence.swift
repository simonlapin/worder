import Foundation
import SwiftData

/// A generated example sentence cached for offline use in context exercises.
@Model
public final class CachedSentence {
    public var en: String
    public var ru: String
    public var createdAt: Date

    public var word: Word?

    public init(en: String, ru: String, createdAt: Date) {
        self.en = en
        self.ru = ru
        self.createdAt = createdAt
    }
}
