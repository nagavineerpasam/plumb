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

    func testEditingOneSentenceRescoresOnlyThatSentence() async {
        let client = FakeSignalClient()
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)
        analyzer.update(text: "First sentence. Second sentence. Third sentence.")
        await analyzer.idle()

        analyzer.update(text: "First sentence. Second sentence, edited. Third sentence.")
        await analyzer.idle()

        XCTAssertEqual(client.requests.last, ["Second sentence, edited."])
        XCTAssertTrue(analyzer.sentences.allSatisfy { $0.signals != nil })
    }

    func testResultForTextThatChangedMeanwhileIsNeverShown() async {
        let client = FakeSignalClient()
        let (release, releaser) = AsyncStream.makeStream(of: Void.self)
        client.gate = release.makeAsyncIterator()
        client.grammarMistake = ["Draft sentence."]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "Draft sentence.")
        await Task.yield()
        analyzer.update(text: "Final sentence.")
        releaser.yield()
        releaser.yield()
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map(\.text), ["Final sentence."])
        XCTAssertEqual(analyzer.sentences.first?.signals?.signals["grammar"]?.value, "no")
    }

    func testSummaryAggregatesTheNote() async {
        func signals(grammar: String, tone: String, emotion: String,
                     confidence: Double, clarity: Double, formality: Double) -> [String: Signal] {
            ["grammar": Signal(value: grammar, distribution: [:]),
             "tone": Signal(value: tone, distribution: [:]),
             "emotion": Signal(value: emotion, distribution: [:]),
             "confidence": Signal(value: "", distribution: [:], score: confidence),
             "clarity": Signal(value: "", distribution: [:], score: clarity),
             "formality": Signal(value: "", distribution: [:], score: formality)]
        }
        let client = FakeSignalClient()
        client.script = [
            "One.": signals(grammar: "yes", tone: "formal", emotion: "joy", confidence: 1.0, clarity: 0.5, formality: 1.0),
            "Two.": signals(grammar: "no", tone: "formal", emotion: "anger", confidence: 0.5, clarity: 1.0, formality: 0.5),
            "Three.": signals(grammar: "no", tone: "casual", emotion: "joy", confidence: 0.0, clarity: 0.0, formality: 0.0),
            "Four.": signals(grammar: "no", tone: "casual", emotion: "joy", confidence: 0.5, clarity: 0.5, formality: 0.5),
        ]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "One. Two. Three. Four.")
        await analyzer.idle()
        let summary = analyzer.summary

        XCTAssertEqual(summary.scoredSentences, 4)
        XCTAssertEqual(summary.grammarErrorRate, 0.25)
        XCTAssertEqual(summary.tone, ["formal": 0.5, "casual": 0.5])
        XCTAssertEqual(summary.emotion, ["joy": 0.75, "anger": 0.25])
        XCTAssertEqual(summary.confidence, 0.5)
        XCTAssertEqual(summary.clarity, 0.5)
        XCTAssertEqual(summary.formality, 0.5)
    }

    func testEmptyNoteHasEmptySummary() {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        XCTAssertEqual(analyzer.summary.scoredSentences, 0)
        XCTAssertNil(analyzer.summary.grammarErrorRate)
        XCTAssertNil(analyzer.summary.confidence)
    }

    func testSignalsComeBackAfterTheWorkerCrashes() async {
        let client = FakeSignalClient()
        client.failures = 2
        let analyzer = NoteAnalyzer(client: client, debounce: .zero, retryDelay: .zero)

        analyzer.update(text: "Still here.")
        await analyzer.idle()

        XCTAssertEqual(client.requests.count, 3)
        XCTAssertNotNil(analyzer.sentences.first?.signals)
    }

    func testSplitsSentencesInAnyLanguage() {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "Dr. Smith arrived. He sat down.")
        XCTAssertEqual(analyzer.sentences.map(\.text), ["Dr. Smith arrived.", "He sat down."])

        analyzer.update(text: "Das ist z. B. gut. Wir gehen jetzt!")
        XCTAssertEqual(analyzer.sentences.map(\.text), ["Das ist z. B. gut.", "Wir gehen jetzt!"])

        analyzer.update(text: "मैं घर जा रहा हूँ। तुम कहाँ हो?")
        XCTAssertEqual(analyzer.sentences.map(\.text), ["मैं घर जा रहा हूँ।", "तुम कहाँ हो?"])
    }

    func testMechanicsFlagsCapitalizationAndPunctuation() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "hello how are you? Yesterday i went home. Is everything right")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) }, [
            [.lowercaseStart],
            [.lowercaseI],
            [.missingEndPunctuation],
        ])
        XCTAssertEqual(analyzer.summary.mechanicsIssues, 3)
    }

    func testMechanicsCatchesRepeatedWordsAndExtraSpaces() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "We went to the the park.  It was  sunny.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) }, [[.repeatedWord], [.extraSpace]])
    }

    func testSentenceStartingWithLowercaseIIsFlaggedOnce() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "i think so. i.e. we wait.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.first?.mechanics?.map(\.kind), [.lowercaseStart])
    }

    func testCleanSentencesHaveNoMechanicsIssues() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "Hello, how are you? \"Is everything right?\" I asked. 3 people came!")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics }, [[], [], []])
        XCTAssertEqual(analyzer.summary.mechanicsIssues, 0)
    }

    func testMechanicsWaitForThePauseLikeTheOtherSignals() {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .seconds(60))

        analyzer.update(text: "is everything right")

        XCTAssertNil(analyzer.sentences.first?.mechanics)
    }

    func testMisspelledWordsAreMarkedWithoutSuggestions() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "We should seperate the reports untill Friday.")
        await analyzer.idle()

        let spelling = analyzer.sentences.first?.mechanics?.filter { $0.kind == .spelling } ?? []
        XCTAssertEqual(spelling.map(\.word), ["seperate", "untill"])
        let text = analyzer.sentences[0].text as NSString
        XCTAssertEqual(spelling.compactMap(\.range).map { text.substring(with: $0) }, ["seperate", "untill"])
    }
}
