import Foundation
import SwiftData
import Testing
@testable import WorderCore

private let now = Date(timeIntervalSince1970: 1_750_000_000)

/// Deterministic SplitMix64 generator for reproducible selection tests.
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

private func card(state: CardState, stability: Double) -> SchedulerCard {
    SchedulerCard(state: state, stability: stability, difficulty: 5, due: now)
}

private func selectTypes(
    card: SchedulerCard,
    direction: Direction,
    capabilities: ExerciseSelector.Capabilities,
    draws: Int = 40
) -> Set<ExerciseType> {
    let selector = ExerciseSelector()
    var rng = SeededGenerator(seed: 42)
    var seen = Set<ExerciseType>()
    for _ in 0..<draws {
        seen.insert(selector.exerciseType(
            for: card, direction: direction, capabilities: capabilities, using: &rng
        ))
    }
    return seen
}

@Suite struct ExerciseSelectorLadderTests {
    private let allCapabilities = ExerciseSelector.Capabilities(hasCachedSentences: true, canPlayAudio: true)

    @Test(arguments: [CardState.new, .learning, .relearning])
    func nonReviewCardsAlwaysGetMultipleChoice(state: CardState) {
        for direction in Direction.allCases {
            let types = selectTypes(
                card: card(state: state, stability: 50),
                direction: direction,
                capabilities: allCapabilities
            )
            #expect(types == [.multipleChoice])
        }
    }

    @Test func youngReviewCardsGetMultipleChoiceInBothDirections() {
        let young = card(state: .review, stability: 2)
        #expect(selectTypes(card: young, direction: .enToRu, capabilities: allCapabilities) == [.multipleChoice])
        #expect(selectTypes(card: young, direction: .ruToEn, capabilities: allCapabilities) == [.multipleChoice])
    }

    @Test func establishedRuToEnSwitchesToTypedAnswer() {
        let developing = card(state: .review, stability: 5)
        #expect(selectTypes(card: developing, direction: .ruToEn, capabilities: allCapabilities) == [.typedAnswer])
        #expect(selectTypes(card: developing, direction: .enToRu, capabilities: allCapabilities) == [.multipleChoice])
    }

    @Test func matureCardsMixInListeningAndContext() {
        let mature = card(state: .review, stability: 30)
        #expect(selectTypes(card: mature, direction: .enToRu, capabilities: allCapabilities)
            == [.multipleChoice, .listening])
        #expect(selectTypes(card: mature, direction: .ruToEn, capabilities: allCapabilities)
            == [.typedAnswer, .context])
    }

    @Test func matureCardsWithoutCapabilitiesStayOnBaseTypes() {
        let mature = card(state: .review, stability: 30)
        let none = ExerciseSelector.Capabilities()
        #expect(selectTypes(card: mature, direction: .enToRu, capabilities: none) == [.multipleChoice])
        #expect(selectTypes(card: mature, direction: .ruToEn, capabilities: none) == [.typedAnswer])
    }

    @Test func contextRequiresSentencesAndListeningRequiresAudio() {
        let mature = card(state: .review, stability: 30)
        let audioOnly = ExerciseSelector.Capabilities(hasCachedSentences: false, canPlayAudio: true)
        let sentencesOnly = ExerciseSelector.Capabilities(hasCachedSentences: true, canPlayAudio: false)

        #expect(selectTypes(card: mature, direction: .ruToEn, capabilities: audioOnly) == [.typedAnswer])
        #expect(selectTypes(card: mature, direction: .enToRu, capabilities: sentencesOnly) == [.multipleChoice])
    }

    @Test func selectionIsDeterministicForTheSameSeed() {
        let selector = ExerciseSelector()
        let mature = card(state: .review, stability: 30)
        let capabilities = ExerciseSelector.Capabilities(hasCachedSentences: true, canPlayAudio: true)

        var firstRng = SeededGenerator(seed: 7)
        var secondRng = SeededGenerator(seed: 7)
        let first = (0..<20).map { _ in
            selector.exerciseType(for: mature, direction: .enToRu, capabilities: capabilities, using: &firstRng)
        }
        let second = (0..<20).map { _ in
            selector.exerciseType(for: mature, direction: .enToRu, capabilities: capabilities, using: &secondRng)
        }
        #expect(first == second)
    }
}

@Suite struct LeechDetectorTests {
    private func makeWord(_ context: ModelContext, lapses: [Direction: Int]) -> Word {
        let word = Word(wordId: 1, text: "shop", translations: ["магазин"])
        context.insert(word)
        for direction in Direction.allCases {
            let state = DirectionState(direction: direction, due: now, lapses: lapses[direction] ?? 0)
            context.insert(state)
            state.word = word
        }
        return word
    }

    @Test func wordBelowThresholdIsNotALeech() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context, lapses: [.enToRu: 5, .ruToEn: 5])
        #expect(!LeechDetector().isLeech(word))
    }

    @Test func anyDirectionAtThresholdMakesALeech() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context, lapses: [.enToRu: 0, .ruToEn: 6])
        #expect(LeechDetector().isLeech(word))
    }

    @Test func customThresholdIsRespected() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let word = makeWord(context, lapses: [.enToRu: 3])
        #expect(LeechDetector(lapseThreshold: 3).isLeech(word))
        #expect(!LeechDetector(lapseThreshold: 4).isLeech(word))
    }

    @Test func updateFlagPersistsAndListsLeeches() throws {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        let detector = LeechDetector()
        let leech = makeWord(context, lapses: [.enToRu: 6])
        let healthy = Word(wordId: 2, text: "store", translations: ["магазин"])
        context.insert(healthy)

        #expect(detector.updateFlag(for: leech))
        #expect(!detector.updateFlag(for: healthy))
        try context.save()

        let leeches = try detector.leeches(in: context)
        #expect(leeches.count == 1)
        #expect(leeches.first === leech)
    }
}
