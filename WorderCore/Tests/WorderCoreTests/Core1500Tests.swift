import Foundation
import Testing
@testable import WorderCore

/// Validates the real reference batch produced by scripts/convert_pdf.py.
/// The file is resolved relative to this source file (tests run on the host),
/// so the repo's data/core-1500.json is checked directly without a copy.
@Suite struct Core1500Tests {
    private static let batch: WordBatchFile = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WorderCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // WorderCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("data/core-1500.json")
        guard let data = try? Data(contentsOf: url),
              let batch = try? WordBatchFile.decode(from: data) else {
            fatalError("data/core-1500.json is missing or invalid — run scripts/convert_pdf.py")
        }
        return batch
    }()

    @Test func decodesWithExpectedMetadata() {
        #expect(Self.batch.batchId == "core-1500")
        #expect(Self.batch.schemaVersion == WordBatchFile.supportedSchemaVersion)
        #expect(Self.batch.words.count == 1500)
    }

    @Test func idsCoverExactRangeWithoutGaps() {
        #expect(Set(Self.batch.words.map(\.id)) == Set(1...1500))
    }

    @Test func englishWordsAreUnique() {
        let words = Self.batch.words.map(\.word)
        #expect(Set(words).count == words.count)
    }

    @Test func firstWordIsArticleWithNote() throws {
        let the = try #require(Self.batch.words.first { $0.id == 1 })
        #expect(the.word == "the")
        #expect(the.translations == ["артикль"])
        #expect(the.note == "определённый")
    }

    @Test func ringHasBothMeanings() throws {
        let ring = try #require(Self.batch.words.first { $0.word == "ring" })
        #expect(Set(ring.translations).isSuperset(of: ["кольцо", "звонить"]))
    }

    @Test func shopAndStoreShareATranslation() throws {
        let shop = try #require(Self.batch.words.first { $0.word == "shop" })
        let store = try #require(Self.batch.words.first { $0.word == "store" })
        #expect(!Set(shop.translations).intersection(store.translations).isEmpty)
    }

    @Test func wrappedRowsWereReassembled() throws {
        // #1342 spans two text lines in the PDF (number and word both wrap).
        let entry = try #require(Self.batch.words.first { $0.id == 1342 })
        #expect(entry.word == "uncomfortable")
        #expect(entry.translations == ["неудобный"])
    }
}
