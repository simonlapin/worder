import Foundation
import SwiftData

/// Answers "which English words have translation X" — the foundation for
/// synonym-aware answer checking and distractor exclusion.
///
/// Keys are normalized (case, ё→е, whitespace), so «Самолёт» and «самолет»
/// resolve to the same entry. Rebuild from the database after each import.
public struct TranslationIndex: Equatable, Sendable {
    private var englishWordsByTranslation: [String: Set<String>] = [:]

    public init() {}

    public init(context: ModelContext) throws {
        for word in try context.fetch(FetchDescriptor<Word>()) {
            add(word: word.text, translations: word.translations)
        }
    }

    public mutating func add(word: String, translations: [String]) {
        for translation in translations {
            englishWordsByTranslation[Self.normalize(translation), default: []].insert(word)
        }
    }

    public func englishWords(for translation: String) -> Set<String> {
        englishWordsByTranslation[Self.normalize(translation)] ?? []
    }

    /// Case-, ё/е- and whitespace-insensitive key for Russian translations.
    public static func normalize(_ translation: String) -> String {
        translation
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
