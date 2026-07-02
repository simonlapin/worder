import Foundation
import SwiftData
import Testing
@testable import WorderCore

@Suite struct DamerauLevenshteinTests {
    @Test func equalStringsHaveZeroDistance() {
        #expect(DamerauLevenshtein.distance("receive", "receive") == 0)
        #expect(DamerauLevenshtein.distance("", "") == 0)
    }

    @Test func singleEditsHaveDistanceOne() {
        #expect(DamerauLevenshtein.distance("recieve", "receive") == 1)  // transposition
        #expect(DamerauLevenshtein.distance("shap", "shop") == 1)  // substitution
        #expect(DamerauLevenshtein.distance("shoop", "shop") == 1)  // insertion
        #expect(DamerauLevenshtein.distance("shp", "shop") == 1)  // deletion
    }

    @Test func multipleEditsAccumulate() {
        #expect(DamerauLevenshtein.distance("stroe", "shop") == 3)
        #expect(DamerauLevenshtein.distance("cat", "dog") == 3)
        #expect(DamerauLevenshtein.distance("reciev", "receive") == 2)
    }

    @Test func emptyStringCostsFullLength() {
        #expect(DamerauLevenshtein.distance("", "shop") == 4)
        #expect(DamerauLevenshtein.distance("shop", "") == 4)
    }

    @Test func worksOnCyrillicCharacters() {
        #expect(DamerauLevenshtein.distance("получить", "получать") == 1)
        #expect(DamerauLevenshtein.distance("маашина", "машина") == 1)
    }
}

private func makeIndex() -> TranslationIndex {
    var index = TranslationIndex()
    index.add(word: "shop", translations: ["магазин"])
    index.add(word: "store", translations: ["магазин"])
    index.add(word: "ring", translations: ["кольцо", "звонить"])
    index.add(word: "cat", translations: ["кот"])
    index.add(word: "receive", translations: ["получать"])
    index.add(word: "plane", translations: ["самолёт"])
    index.add(word: "airplane", translations: ["самолёт"])
    return index
}

@Suite struct AnswerCheckerEnToRuTests {
    private let checker = AnswerChecker(index: makeIndex())

    @Test func exactTranslationIsCorrect() {
        #expect(checker.check("магазин", direction: .enToRu, wordText: "shop", translations: ["магазин"]) == .correct)
    }

    @Test func caseWhitespaceAndYoAreNormalized() {
        #expect(checker.check("  МАГАЗИН ", direction: .enToRu, wordText: "shop", translations: ["магазин"]) == .correct)
        #expect(checker.check("самолет", direction: .enToRu, wordText: "plane", translations: ["самолёт"]) == .correct)
        #expect(checker.check("иметь  в\tвиду", direction: .enToRu, wordText: "mean", translations: ["иметь в виду"]) == .correct)
    }

    @Test func anyOfSeveralMeaningsIsCorrect() {
        let translations = ["кольцо", "звонить"]
        #expect(checker.check("кольцо", direction: .enToRu, wordText: "ring", translations: translations) == .correct)
        #expect(checker.check("звонить", direction: .enToRu, wordText: "ring", translations: translations) == .correct)
    }

    @Test func singleEditTypoIsAlmostCorrect() {
        #expect(checker.check("получить", direction: .enToRu, wordText: "receive", translations: ["получать"]) == .almostCorrect)
        #expect(checker.check("клоьцо", direction: .enToRu, wordText: "ring", translations: ["кольцо", "звонить"]) == .almostCorrect)
    }

    @Test func shortTranslationGetsNoTypoTolerance() {
        #expect(checker.check("кит", direction: .enToRu, wordText: "cat", translations: ["кот"]) == .wrong)
    }

    @Test func unrelatedOrEmptyAnswerIsWrong() {
        #expect(checker.check("собака", direction: .enToRu, wordText: "cat", translations: ["кот"]) == .wrong)
        #expect(checker.check("   ", direction: .enToRu, wordText: "cat", translations: ["кот"]) == .wrong)
    }
}

@Suite struct AnswerCheckerRuToEnTests {
    private let checker = AnswerChecker(index: makeIndex())

    @Test func exactWordIsCorrect() {
        #expect(checker.check("shop", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .correct)
        #expect(checker.check("  SHOP ", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .correct)
    }

    @Test func validSynonymIsCorrectSynonym() {
        #expect(
            checker.check("store", direction: .ruToEn, wordText: "shop", translations: ["магазин"])
                == .correctSynonym(intended: "shop")
        )
        #expect(
            checker.check("airplane", direction: .ruToEn, wordText: "plane", translations: ["самолёт"])
                == .correctSynonym(intended: "plane")
        )
    }

    @Test func singleEditTypoOfExpectedWordIsAlmostCorrect() {
        #expect(checker.check("recieve", direction: .ruToEn, wordText: "receive", translations: ["получать"]) == .almostCorrect)
        #expect(checker.check("shoop", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .almostCorrect)
    }

    @Test func singleEditTypoOfSynonymIsAlmostCorrect() {
        #expect(checker.check("stor", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .almostCorrect)
    }

    @Test func shortWordGetsNoTypoTolerance() {
        #expect(checker.check("cut", direction: .ruToEn, wordText: "cat", translations: ["кот"]) == .wrong)
        #expect(checker.check("ca", direction: .ruToEn, wordText: "cat", translations: ["кот"]) == .wrong)
    }

    @Test func unrelatedOrEmptyAnswerIsWrong() {
        #expect(checker.check("dog", direction: .ruToEn, wordText: "cat", translations: ["кот"]) == .wrong)
        #expect(checker.check("", direction: .ruToEn, wordText: "cat", translations: ["кот"]) == .wrong)
    }

    @Test func synonymLookupIgnoresTranslationsAbsentFromIndex() {
        let checker = AnswerChecker(index: TranslationIndex())
        #expect(checker.check("store", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .wrong)
        #expect(checker.check("shoop", direction: .ruToEn, wordText: "shop", translations: ["магазин"]) == .almostCorrect)
    }
}

@Suite struct AnswerVerdictGradeTests {
    @Test func verdictsMapToReviewGrades() {
        #expect(AnswerVerdict.correct.reviewGrade == .good)
        #expect(AnswerVerdict.correctSynonym(intended: "shop").reviewGrade == .good)
        #expect(AnswerVerdict.almostCorrect.reviewGrade == .hard)
        #expect(AnswerVerdict.wrong.reviewGrade == .again)
    }
}

@Suite struct AnswerCheckerCore1500Tests {
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeCore1500Checker() throws -> (AnswerChecker, ModelContext) {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WorderCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // WorderCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("data/core-1500.json")
        try BatchImporter(context: context).importBatch(from: Data(contentsOf: url), now: Self.now)
        return (AnswerChecker(index: try TranslationIndex(context: context)), context)
    }

    private func translations(of text: String, in context: ModelContext) throws -> [String] {
        let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.text == text }))
        return try #require(words.first).translations
    }

    @Test func synonymPairsFromRealDataAreAccepted() throws {
        let (checker, context) = try makeCore1500Checker()

        let shop = try translations(of: "shop", in: context)
        #expect(checker.check("store", direction: .ruToEn, wordText: "shop", translations: shop) == .correctSynonym(intended: "shop"))

        let car = try translations(of: "car", in: context)
        #expect(checker.check("machine", direction: .ruToEn, wordText: "car", translations: car) == .correctSynonym(intended: "car"))

        let plane = try translations(of: "plane", in: context)
        #expect(checker.check("airplane", direction: .ruToEn, wordText: "plane", translations: plane) == .correctSynonym(intended: "plane"))
    }

    @Test func multiMeaningWordAcceptsEachMeaning() throws {
        let (checker, context) = try makeCore1500Checker()
        let ring = try translations(of: "ring", in: context)

        #expect(checker.check("кольцо", direction: .enToRu, wordText: "ring", translations: ring) == .correct)
        #expect(checker.check("звонить", direction: .enToRu, wordText: "ring", translations: ring) == .correct)
    }
}
