import Foundation

/// Canonical word-batch file format — the contract for all word deliveries.
/// See README.md ("Формат пачки слов") for the documented schema.
public struct WordBatchFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public struct Sentence: Codable, Equatable, Sendable {
        public let en: String
        public let ru: String

        public init(en: String, ru: String) {
            self.en = en
            self.ru = ru
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let id: Int
        public let word: String
        public let translations: [String]
        public let note: String?
        public let category: String?
        public let sentences: [Sentence]?

        public init(
            id: Int,
            word: String,
            translations: [String],
            note: String? = nil,
            category: String? = nil,
            sentences: [Sentence]? = nil
        ) {
            self.id = id
            self.word = word
            self.translations = translations
            self.note = note
            self.category = category
            self.sentences = sentences
        }
    }

    public let schemaVersion: Int
    public let batchId: String
    public let title: String
    public let category: String?
    public let words: [Entry]

    public init(
        schemaVersion: Int = WordBatchFile.supportedSchemaVersion,
        batchId: String,
        title: String,
        category: String? = nil,
        words: [Entry]
    ) {
        self.schemaVersion = schemaVersion
        self.batchId = batchId
        self.title = title
        self.category = category
        self.words = words
    }
}

public enum WordBatchFileError: Error, Equatable, CustomStringConvertible {
    case malformedJSON(underlying: String)
    case unsupportedSchemaVersion(Int)
    case emptyBatchId
    case emptyTitle
    case noWords
    case emptyWord(id: Int)
    case emptyTranslations(id: Int, word: String)
    case duplicateId(Int)
    case emptySentence(id: Int, word: String)

    public var description: String {
        switch self {
        case .malformedJSON(let underlying):
            "Batch file is not valid JSON for the expected schema: \(underlying)"
        case .unsupportedSchemaVersion(let version):
            "Unsupported schemaVersion \(version); this app supports \(WordBatchFile.supportedSchemaVersion)"
        case .emptyBatchId:
            "batchId must be a non-empty string"
        case .emptyTitle:
            "title must be a non-empty string"
        case .noWords:
            "Batch contains no words"
        case .emptyWord(let id):
            "Word #\(id) has an empty `word` field"
        case .emptyTranslations(let id, let word):
            "Word #\(id) (\(word)) has no non-empty translations"
        case .duplicateId(let id):
            "Duplicate word id #\(id)"
        case .emptySentence(let id, let word):
            "Word #\(id) (\(word)) has a sentence with an empty side"
        }
    }
}

extension WordBatchFile {
    /// Decodes and strictly validates a batch file.
    public static func decode(from data: Data) throws -> WordBatchFile {
        let file: WordBatchFile
        do {
            file = try JSONDecoder().decode(WordBatchFile.self, from: data)
        } catch {
            throw WordBatchFileError.malformedJSON(underlying: String(describing: error))
        }
        try file.validate()
        return file
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw WordBatchFileError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !batchId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WordBatchFileError.emptyBatchId
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WordBatchFileError.emptyTitle
        }
        guard !words.isEmpty else {
            throw WordBatchFileError.noWords
        }

        var seenIds = Set<Int>()
        for entry in words {
            guard seenIds.insert(entry.id).inserted else {
                throw WordBatchFileError.duplicateId(entry.id)
            }
            guard !entry.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WordBatchFileError.emptyWord(id: entry.id)
            }
            let nonEmptyTranslations = entry.translations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !nonEmptyTranslations.isEmpty, nonEmptyTranslations.count == entry.translations.count else {
                throw WordBatchFileError.emptyTranslations(id: entry.id, word: entry.word)
            }
            for sentence in entry.sentences ?? [] {
                let en = sentence.en.trimmingCharacters(in: .whitespacesAndNewlines)
                let ru = sentence.ru.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !en.isEmpty, !ru.isEmpty else {
                    throw WordBatchFileError.emptySentence(id: entry.id, word: entry.word)
                }
            }
        }
    }
}
