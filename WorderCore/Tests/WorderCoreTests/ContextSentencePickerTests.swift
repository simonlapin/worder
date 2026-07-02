import Foundation
import Testing
@testable import WorderCore

private struct FixedRNG: RandomNumberGenerator {
    var value: UInt64

    mutating func next() -> UInt64 {
        value
    }
}

struct ContextSentencePickerTests {
    private typealias Sentence = WordBatchFile.Sentence
    private let picker = ContextSentencePicker()

    private func pick(word: String, sentences: [Sentence], rngValue: UInt64 = 0) -> ContextSentencePicker.MaskedSentence? {
        var rng = FixedRNG(value: rngValue)
        return picker.pick(wordText: word, sentences: sentences, using: &rng)
    }

    @Test func masksTheWordCaseInsensitively() {
        let result = pick(word: "shop", sentences: [
            Sentence(en: "Shop opens at nine.", ru: "Магазин открывается в девять.")
        ])
        #expect(result == ContextSentencePicker.MaskedSentence(
            masked: "____ opens at nine.",
            translation: "Магазин открывается в девять."
        ))
    }

    @Test func masksEveryOccurrenceSoNoneRevealsTheAnswer() {
        let result = pick(word: "dog", sentences: [
            Sentence(en: "A dog sees another dog.", ru: "Собака видит другую собаку.")
        ])
        #expect(result?.masked == "A ____ sees another ____.")
    }

    @Test func doesNotMatchInsideOtherWords() {
        let result = pick(word: "car", sentences: [
            Sentence(en: "I care about you.", ru: "Я забочусь о тебе.")
        ])
        #expect(result == nil)
        #expect(!picker.hasUsableSentence(wordText: "car", sentences: [
            Sentence(en: "I care about you.", ru: "Я забочусь о тебе.")
        ]))
    }

    @Test func inflectedFormsDoNotCount() {
        let sentences = [Sentence(en: "Two shops are closed.", ru: "Два магазина закрыты.")]
        #expect(pick(word: "shop", sentences: sentences) == nil)
    }

    @Test func skipsUnusableSentencesAndPicksAmongUsable() {
        let sentences = [
            Sentence(en: "Nothing relevant here.", ru: "Ничего подходящего."),
            Sentence(en: "The cat sleeps.", ru: "Кот спит.")
        ]
        let result = pick(word: "cat", sentences: sentences)
        #expect(result?.masked == "The ____ sleeps.")
        #expect(picker.hasUsableSentence(wordText: "cat", sentences: sentences))
    }

    @Test func multiWordEntriesAreMasked() {
        let result = pick(word: "each other", sentences: [
            Sentence(en: "They love each other.", ru: "Они любят друг друга.")
        ])
        #expect(result?.masked == "They love ____.")
    }

    @Test func emptyInputsYieldNothing() {
        #expect(pick(word: "  ", sentences: [Sentence(en: "Any.", ru: "Любое.")]) == nil)
        #expect(pick(word: "dog", sentences: []) == nil)
        #expect(!picker.hasUsableSentence(wordText: "dog", sentences: []))
    }
}
