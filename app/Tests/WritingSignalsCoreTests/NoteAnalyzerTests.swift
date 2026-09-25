import XCTest
import WritingSignalsCore

@MainActor
final class NoteAnalyzerTests: XCTestCase {
    func testTypedSentenceGetsItsGrammarSignal() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["She go to school yesterday."]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "She go to school yesterday.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map(\.text), ["She go to school yesterday."])
        XCTAssertEqual(analyzer.sentences.first?.signals?.signals["grammar"]?.value, "yes")
    }
}
