import Foundation
import SwiftData
import Testing
@testable import WorderCore

/// Deterministic SplitMix64 generator for reproducible sampling tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func candidate(
    _ text: String,
    _ translations: [String],
    category: String? = nil
) -> DistractorCandidate {
    DistractorCandidate(text: text, translations: translations, category: category)
}

@Suite struct DistractorGeneratorTests {
    private let generator = DistractorGenerator()
    private let shop = candidate("shop", ["магазин"])
    private let pool = [
        candidate("shop", ["магазин"]),
        candidate("store", ["магазин"]),
        candidate("SHOP", ["лавка"]),
        candidate("market", ["Магазин"]),
        candidate("ring", ["кольцо", "звонить"]),
        candidate("cat", ["кот"]),
        candidate("dog", ["собака"]),
        candidate("plane", ["самолёт"]),
        candidate("book", ["книга"]),
        candidate("tree", ["дерево"]),
        candidate("sun", ["солнце"]),
    ]

    @Test func producesExactlyThreeUniqueDistractorsExcludingSynonymsAndTarget() throws {
        for seed in UInt64(0)..<20 {
            var rng = SeededGenerator(seed: seed)
            let options = try generator.distractors(for: shop, direction: .ruToEn, candidates: pool, using: &rng)

            #expect(options.count == 3)
            #expect(Set(options).count == 3)
            // shop itself (any casing), store and market share «магазин» — banned.
            #expect(!options.contains { ["shop", "store", "market"].contains($0.lowercased()) })
        }
    }

    @Test func enToRuOptionsNeverOverlapTargetTranslations() throws {
        let ring = candidate("ring", ["кольцо", "звонить"])
        let poolWithCall = pool + [candidate("call", ["звонить", "звонок"])]
        for seed in UInt64(0)..<20 {
            var rng = SeededGenerator(seed: seed)
            let options = try generator.distractors(for: ring, direction: .enToRu, candidates: poolWithCall, using: &rng)

            #expect(options.count == 3)
            let normalized = Set(options.map(TranslationIndex.normalize))
            #expect(normalized.isDisjoint(with: ["кольцо", "звонить", "звонок"]))
        }
    }

    @Test func duplicateOptionStringsAreDeduplicated() throws {
        let candidates = [
            candidate("house", ["дом"]),
            candidate("home", ["дом"]),
            candidate("book", ["книга"]),
            candidate("sun", ["солнце"]),
        ]
        var rng = SeededGenerator(seed: 1)
        let options = try generator.distractors(
            for: candidate("cat", ["кот"]),
            direction: .enToRu,
            candidates: candidates,
            using: &rng
        )
        #expect(Set(options) == ["дом", "книга", "солнце"])
    }

    @Test func throwsWhenEligibleCandidatesAreScarce() {
        let candidates = [
            candidate("store", ["магазин"]),
            candidate("book", ["книга"]),
            candidate("sun", ["солнце"]),
        ]
        var rng = SeededGenerator(seed: 1)
        #expect {
            try generator.distractors(for: shop, direction: .ruToEn, candidates: candidates, using: &rng)
        } throws: { error in
            error as? DistractorGenerator.GenerationError
                == .insufficientCandidates(required: 3, available: 2)
        }
    }

    @Test func sameCategoryOutranksOtherCategories() throws {
        let target = candidate("cat", ["кот"], category: "animals")
        let candidates = [
            candidate("dog", ["собака"], category: "animals"),
            candidate("pig", ["свинья"], category: "animals"),
            candidate("fox", ["лиса"], category: "animals"),
            candidate("book", ["книга"], category: "objects"),
            candidate("tree", ["дерево"], category: "objects"),
            candidate("sun", ["солнце"], category: "objects"),
        ]
        let generator = DistractorGenerator(configuration: .init(count: 3, samplingPoolSize: 3))
        var rng = SeededGenerator(seed: 7)
        let options = try generator.distractors(for: target, direction: .ruToEn, candidates: candidates, using: &rng)
        #expect(Set(options) == ["dog", "pig", "fox"])
    }

    @Test func closerOptionLengthOutranksFartherWithinCategory() throws {
        let target = candidate("cat", ["кот"])
        let candidates = [
            candidate("dog", ["собака"]),
            candidate("sun", ["солнце"]),
            candidate("pig", ["свинья"]),
            candidate("elephant", ["слон"]),
            candidate("crocodile", ["крокодил"]),
        ]
        let generator = DistractorGenerator(configuration: .init(count: 3, samplingPoolSize: 3))
        var rng = SeededGenerator(seed: 7)
        let options = try generator.distractors(for: target, direction: .ruToEn, candidates: candidates, using: &rng)
        #expect(Set(options) == ["dog", "sun", "pig"])
    }

    @Test func samplingIsDeterministicForTheSameSeed() throws {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        let a = try generator.distractors(for: shop, direction: .ruToEn, candidates: pool, using: &first)
        let b = try generator.distractors(for: shop, direction: .ruToEn, candidates: pool, using: &second)
        #expect(a == b)
    }
}

@Suite struct DistractorGeneratorCore1500Tests {
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private struct Core1500 {
        let candidates: [DistractorCandidate]
        let index: TranslationIndex
    }

    private func loadCore1500() throws -> Core1500 {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WorderCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // WorderCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("data/core-1500.json")
        try BatchImporter(context: context).importBatch(from: Data(contentsOf: url), now: Self.now)
        let words = try context.fetch(FetchDescriptor<Word>())
        return Core1500(
            candidates: words.map(DistractorCandidate.init),
            index: try TranslationIndex(context: context)
        )
    }

    private func synonyms(of target: DistractorCandidate, in index: TranslationIndex) -> Set<String> {
        target.translations
            .reduce(into: Set<String>()) { $0.formUnion(index.englishWords(for: $1)) }
    }

    /// Words sharing a translation with another word are the only inputs
    /// where a second correct option could ever sneak in. The exclusion
    /// filter is identical for every word, so a deterministic spread over
    /// the risky set (plus the canonical synonym pairs) proves the property
    /// without a full 1500-word sweep on every test run.
    @Test func synonymRiskWordsNeverGetASecondCorrectOption() throws {
        let core = try loadCore1500()
        let generator = DistractorGenerator()
        let risky = core.candidates.filter { synonyms(of: $0, in: core.index).count > 1 }
        let riskyTexts = Set(risky.map(\.text))
        #expect(riskyTexts.isSuperset(of: ["shop", "store", "plane", "airplane", "car", "machine"]))

        let canonical = Set(["shop", "store", "plane", "airplane", "car", "machine"])
        let step = max(1, risky.count / 40)
        let sampled = stride(from: 0, to: risky.count, by: step).map { risky[$0] }
            + risky.filter { canonical.contains($0.text) }

        for (offset, target) in sampled.enumerated() {
            let banned = synonyms(of: target, in: core.index)
            let bannedTranslations = Set(target.translations.map(TranslationIndex.normalize))
            var rng = SeededGenerator(seed: UInt64(offset))

            let words = try generator.distractors(
                for: target, direction: .ruToEn, candidates: core.candidates, using: &rng
            )
            #expect(words.count == 3)
            #expect(banned.isDisjoint(with: words), "ruToEn \(target.text): \(words)")

            let options = try generator.distractors(
                for: target, direction: .enToRu, candidates: core.candidates, using: &rng
            )
            #expect(options.count == 3)
            #expect(
                bannedTranslations.isDisjoint(with: options.map(TranslationIndex.normalize)),
                "enToRu \(target.text): \(options)"
            )
        }
    }

    @Test func shopQuestionNeverOffersStore() throws {
        let core = try loadCore1500()
        let generator = DistractorGenerator()
        let shop = try #require(core.candidates.first { $0.text == "shop" })

        for seed in UInt64(0)..<10 {
            var rng = SeededGenerator(seed: seed)
            let options = try generator.distractors(
                for: shop, direction: .ruToEn, candidates: core.candidates, using: &rng
            )
            // The full option set shown to the user: shop (correct) + distractors.
            let shown = Set(options + [shop.text])
            #expect(shown.count == 4)
            #expect(!shown.contains("store"))
        }
    }

    @Test func broadSampleAlwaysYieldsThreeValidOptions() throws {
        let core = try loadCore1500()
        let generator = DistractorGenerator()

        for target in core.candidates.prefix(50) {
            var rng = SeededGenerator(seed: UInt64(target.text.count))
            let words = try generator.distractors(
                for: target, direction: .ruToEn, candidates: core.candidates, using: &rng
            )
            #expect(words.count == 3)
            #expect(!words.contains(target.text))
            #expect(synonyms(of: target, in: core.index).isDisjoint(with: words))
        }
    }
}
