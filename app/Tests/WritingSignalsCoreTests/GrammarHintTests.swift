import XCTest
@testable import WritingSignalsCore

final class GrammarHintTests: XCTestCase {
    let sentence = "Yesterday I goes to the gym."
    var goes: WordPointer { WordPointer(text: "goes", start: 12, end: 16, probability: 0.93) }

    func testThePointerNamesTheWordAndAddsMacOSsFixForThatWord() {
        let mac = GrammarDetail(range: NSRange(location: 12, length: 4), message: "“goes” doesn’t agree with the rest of the sentence.", fixes: ["went"])
        XCTAssertEqual(GrammarHint.line(for: sentence, pointer: goes, macOS: mac), "“goes” looks wrong here. Try “went”.")
        XCTAssertEqual(GrammarHint.short(for: sentence, pointer: goes, macOS: mac), "“goes” → “went”")
    }

    func testAFixForADifferentWordIsNotOffered() {
        let elsewhere = GrammarDetail(range: NSRange(location: 0, length: 9), message: "…", fixes: ["Today"])
        XCTAssertEqual(GrammarHint.line(for: sentence, pointer: goes, macOS: elsewhere), "“goes” looks wrong here.")
        XCTAssertEqual(GrammarHint.short(for: sentence, pointer: goes, macOS: nil), "Check “goes”")
    }

    func testWithoutAPointerItFallsBackToMacOSThenToTheGeneralHint() {
        let mac = GrammarDetail(range: NSRange(location: 12, length: 4), message: "“goes” doesn’t agree with the rest of the sentence.", fixes: ["went"])
        XCTAssertEqual(GrammarHint.line(for: sentence, pointer: nil, macOS: mac), "“goes” doesn’t agree with the rest of the sentence. Try “went”.")
        XCTAssertEqual(GrammarHint.line(for: sentence, pointer: nil, macOS: nil), GrammarHint.general)
        XCTAssertEqual(GrammarHint.short(for: sentence, pointer: nil, macOS: nil), "Grammar mistake")
    }
}
