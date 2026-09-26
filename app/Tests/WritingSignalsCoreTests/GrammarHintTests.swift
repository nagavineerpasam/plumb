import XCTest
@testable import WritingSignalsCore

/// The card teaches: it names where the mistake is and what kind it is, never the answer.
final class GrammarHintTests: XCTestCase {
    private func pointer(_ word: String, in sentence: String, type: String?) -> WordPointer {
        let r = (sentence as NSString).range(of: word)
        return WordPointer(text: word, start: r.location, end: NSMaxRange(r), probability: 0.95, type: type, typeProbability: type == nil ? nil : 0.95)
    }

    func testEachTypeTeachesTheRuleWithTheLearnersOwnWord() {
        let s = "Yesterday I goes to the gym."
        XCTAssertEqual(GrammarHint.line(for: s, pointer: pointer("goes", in: s, type: "verb")),
                       "Verb: check the tense and form of “goes”. Which form fits here? “Yesterday” tells you when.")
        XCTAssertEqual(GrammarHint.line(for: "He don't like coffee.", pointer: pointer("don't", in: "He don't like coffee.", type: "agreement")),
                       "Agreement: “don't” doesn’t match the word it goes with. Check who or what it’s about.")
        XCTAssertEqual(GrammarHint.line(for: "I went to shop.", pointer: pointer("shop", in: "I went to shop.", type: "word_missing")),
                       "Missing word: something is missing before “shop”.")
        XCTAssertEqual(GrammarHint.short(for: s, pointer: pointer("goes", in: s, type: "verb")), "“goes” · Verb")
    }

    func testNoHintEverGivesTheAnswer() {
        let s = "We discussed about the plan last week."
        for type in ["verb", "agreement", "article", "preposition", "number", "word_order", "word_missing", "word_extra"] {
            let line = GrammarHint.line(for: s, pointer: pointer("about", in: s, type: type))
            XCTAssertFalse(line.contains("Try"), type)
            XCTAssertTrue(line.contains("“about”"), "\(type) names the learner's word")
        }
    }

    func testItSaysLessInsteadOfGuessing() {
        let s = "They was there."
        XCTAssertEqual(GrammarHint.line(for: s, pointer: pointer("was", in: s, type: nil)), "Check “was”.")
        XCTAssertEqual(GrammarHint.short(for: s, pointer: pointer("was", in: s, type: nil)), "Check “was”")
        XCTAssertEqual(GrammarHint.line(for: s, pointer: nil), GrammarHint.general)
        XCTAssertEqual(GrammarHint.short(for: s, pointer: nil), "Grammar mistake")
    }
}
