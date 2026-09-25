import XCTest
import WritingSignalsCore

@MainActor
final class GrammarExplainerTests: XCTestCase {
    private func word(_ detail: GrammarDetail, in sentence: String) -> String {
        (sentence as NSString).substring(with: detail.range)
    }

    func testFindsTheWordAndOnlyAFixThatWorks() throws {
        let sentence = "The tickets is already booked."
        let detail = try XCTUnwrap(GrammarExplainer.explain(sentence))

        XCTAssertEqual(word(detail, in: sentence), "is")
        XCTAssertEqual(detail.fixes, ["are"], "“am” doesn't fit “tickets”, so it isn't offered")
        XCTAssertEqual(detail.message, "“is” doesn’t agree with the rest of the sentence.")
    }

    func testFindsTheWordEvenWithoutASuggestedFix() throws {
        let sentence = "He go to school every day."
        let detail = try XCTUnwrap(GrammarExplainer.explain(sentence))

        XCTAssertEqual(word(detail, in: sentence), "go")
    }

    func testCorrectSentencesHaveNoDetail() {
        XCTAssertNil(GrammarExplainer.explain("The tickets are already booked."))
        XCTAssertNil(GrammarExplainer.explain("He goes to school every day."))
    }

    func testMistakesItCannotPlaceHaveNoDetail() {
        XCTAssertNil(GrammarExplainer.explain("I am agree with you."))
    }

    func testNeverSuggestsAFixTheCheckerStillFlags() throws {
        for sentence in ["The tickets is already booked.", "We was very tired after.", "The hotel are near the river."] {
            guard let detail = GrammarExplainer.explain(sentence) else { continue }
            for fix in detail.fixes {
                let fixed = (sentence as NSString).replacingCharacters(in: detail.range, with: fix)
                XCTAssertNil(GrammarExplainer.explain(fixed), "“\(fix)” in “\(sentence)”")
            }
        }
    }
}
