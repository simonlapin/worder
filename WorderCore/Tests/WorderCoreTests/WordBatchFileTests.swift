import Foundation
import Testing
@testable import WorderCore

private func data(_ json: String) -> Data {
    Data(json.utf8)
}

private let validBatch = """
{
  "schemaVersion": 1,
  "batchId": "test-batch",
  "title": "Test batch",
  "words": [
    {"id": 1, "word": "the", "translations": ["артикль"], "note": "определённый"},
    {"id": 2, "word": "ring", "translations": ["кольцо", "звонить"]},
    {
      "id": 3,
      "word": "shop",
      "translations": ["магазин"],
      "category": "places",
      "sentences": [{"en": "I went to the shop.", "ru": "Я пошёл в магазин."}]
    }
  ]
}
"""

@Suite struct WordBatchFileDecodingTests {
    @Test func decodesValidBatch() throws {
        let file = try WordBatchFile.decode(from: data(validBatch))
        #expect(file.schemaVersion == 1)
        #expect(file.batchId == "test-batch")
        #expect(file.words.count == 3)
        #expect(file.words[0].note == "определённый")
        #expect(file.words[1].translations == ["кольцо", "звонить"])
        #expect(file.words[2].sentences?.first?.ru == "Я пошёл в магазин.")
        #expect(file.words[2].category == "places")
        #expect(file.category == nil)
    }

    @Test func roundTripsThroughEncoder() throws {
        let file = try WordBatchFile.decode(from: data(validBatch))
        let encoded = try JSONEncoder().encode(file)
        let decoded = try WordBatchFile.decode(from: encoded)
        #expect(decoded == file)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: WordBatchFileError.self) {
            try WordBatchFile.decode(from: data("{\"schemaVersion\": 1"))
        }
    }

    @Test func rejectsMissingRequiredField() {
        // `word` missing on the entry.
        let json = """
        {"schemaVersion": 1, "batchId": "b", "title": "t",
         "words": [{"id": 1, "translations": ["да"]}]}
        """
        #expect(throws: WordBatchFileError.self) {
            try WordBatchFile.decode(from: data(json))
        }
    }
}

@Suite struct WordBatchFileValidationTests {
    private func batch(words: [WordBatchFile.Entry]) -> WordBatchFile {
        WordBatchFile(batchId: "b", title: "t", words: words)
    }

    @Test func rejectsUnsupportedSchemaVersion() {
        let file = WordBatchFile(
            schemaVersion: 99, batchId: "b", title: "t",
            words: [.init(id: 1, word: "yes", translations: ["да"])]
        )
        #expect(throws: WordBatchFileError.unsupportedSchemaVersion(99)) {
            try file.validate()
        }
    }

    @Test func rejectsEmptyBatchId() {
        let file = WordBatchFile(
            batchId: "  ", title: "t",
            words: [.init(id: 1, word: "yes", translations: ["да"])]
        )
        #expect(throws: WordBatchFileError.emptyBatchId) { try file.validate() }
    }

    @Test func rejectsEmptyTitle() {
        let file = WordBatchFile(
            batchId: "b", title: "",
            words: [.init(id: 1, word: "yes", translations: ["да"])]
        )
        #expect(throws: WordBatchFileError.emptyTitle) { try file.validate() }
    }

    @Test func rejectsEmptyWordList() {
        #expect(throws: WordBatchFileError.noWords) {
            try batch(words: []).validate()
        }
    }

    @Test func rejectsEmptyWord() {
        let file = batch(words: [.init(id: 7, word: "   ", translations: ["да"])])
        #expect(throws: WordBatchFileError.emptyWord(id: 7)) { try file.validate() }
    }

    @Test func rejectsEmptyTranslationsList() {
        let file = batch(words: [.init(id: 5, word: "yes", translations: [])])
        #expect(throws: WordBatchFileError.emptyTranslations(id: 5, word: "yes")) {
            try file.validate()
        }
    }

    @Test func rejectsBlankTranslationAmongValid() {
        let file = batch(words: [.init(id: 5, word: "yes", translations: ["да", " "])])
        #expect(throws: WordBatchFileError.emptyTranslations(id: 5, word: "yes")) {
            try file.validate()
        }
    }

    @Test func rejectsDuplicateIds() {
        let file = batch(words: [
            .init(id: 1, word: "yes", translations: ["да"]),
            .init(id: 1, word: "no", translations: ["нет"]),
        ])
        #expect(throws: WordBatchFileError.duplicateId(1)) { try file.validate() }
    }

    @Test func rejectsSentenceWithEmptySide() {
        let file = batch(words: [
            .init(id: 1, word: "yes", translations: ["да"], sentences: [.init(en: "Yes.", ru: "")]),
        ])
        #expect(throws: WordBatchFileError.emptySentence(id: 1, word: "yes")) {
            try file.validate()
        }
    }
}
