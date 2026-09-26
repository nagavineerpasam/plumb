import XCTest
import WritingSignalsCore

final class DictationBufferTests: XCTestCase {
    /// Applies the buffer's edits to a string, the way the editor applies them to the text view.
    private func run(_ text: inout String, _ edit: DictationBuffer.Edit) {
        let ns = NSMutableString(string: text)
        ns.replaceCharacters(in: edit.range, with: edit.replacement)
        text = ns as String
    }

    func testInProgressWordsAreReplacedThenSettleAtTheCursor() {
        var text = "Hello. Bye."
        var buffer = DictationBuffer(selection: NSRange(location: 6, length: 0), in: text)

        run(&text, buffer.volatile("we was"))
        XCTAssertEqual(text, "Hello. we was Bye.")
        XCTAssertEqual((text as NSString).substring(with: buffer.grey!), "we was")

        run(&text, buffer.volatile("we was late"))
        run(&text, buffer.final("We was late.", unsure: []))

        XCTAssertEqual(text, "Hello. We was late. Bye.")
        XCTAssertNil(buffer.grey)
    }

    func testKnowsWhetherAnyDictatedWordsAreShowing() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)
        XCTAssertFalse(buffer.showsWords)

        run(&text, buffer.volatile("you"))       // a phantom word in near-silence...
        run(&text, buffer.volatile(""))          // ...that disappears again
        XCTAssertFalse(buffer.showsWords, "nothing was said after all")

        run(&text, buffer.volatile("We met"))
        XCTAssertTrue(buffer.showsWords)
        run(&text, buffer.final("We met at noon.", unsure: []))
        XCTAssertTrue(buffer.showsWords)
    }

    func testNextPhraseContinuesAfterTheLastOne() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)

        run(&text, buffer.final("I went home.", unsure: []))
        run(&text, buffer.final("It was late.", unsure: []))

        XCTAssertEqual(text, "I went home. It was late.")
    }

    func testSelectionIsReplaced() {
        var text = "Please delete this word now."
        var buffer = DictationBuffer(selection: NSRange(location: 14, length: 4), in: text)

        run(&text, buffer.final("sentence", unsure: []))

        XCTAssertEqual(text, "Please delete sentence word now.")
    }

    func testUnsureWordsBecomeHintsThatFollowEditsAndVanishWhenEdited() {
        var text = "Notes: "
        var buffer = DictationBuffer(selection: NSRange(location: 7, length: 0), in: text)

        // "Kim" (characters 0..<3 of the phrase) was heard with low confidence.
        run(&text, buffer.final("Kim is my friend.", unsure: [NSRange(location: 0, length: 3)]))
        XCTAssertEqual(buffer.hints.map { (text as NSString).substring(with: $0) }, ["Kim"])

        // Typing before the hint moves it along.
        text.insert(contentsOf: "My ", at: text.startIndex)
        buffer.userEdited(NSRange(location: 0, length: 0), replacementLength: 3)
        XCTAssertEqual(buffer.hints.map { (text as NSString).substring(with: $0) }, ["Kim"])

        // Editing the word itself removes the hint.
        buffer.userEdited(NSRange(location: 10, length: 3), replacementLength: 3)
        XCTAssertTrue(buffer.hints.isEmpty)
    }

    func testHintsFromAnEarlierSessionCarryOver() {
        var text = "Kim is here."
        var buffer = DictationBuffer(selection: NSRange(location: 12, length: 0), in: text,
                                     keeping: [NSRange(location: 0, length: 3)])

        run(&text, buffer.final("Bye.", unsure: []))

        XCTAssertEqual(buffer.hints.map { (text as NSString).substring(with: $0) }, ["Kim"])
    }
}
