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

    func testReopeningAnUnchangedNoteShowsItsSignalsWithoutRechecking() async {
        let client = FakeSignalClient()
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)
        analyzer.update(text: "First note is here. It has two sentences.")
        await analyzer.idle()
        analyzer.update(text: "A different note.")
        await analyzer.idle()
        let checksSoFar = client.requests.count

        analyzer.update(text: "First note is here. It has two sentences.")

        XCTAssertTrue(analyzer.sentences.allSatisfy { $0.signals != nil }, "signals show at once, no loading")
        await analyzer.idle()
        XCTAssertEqual(client.requests.count, checksSoFar, "nothing is sent to the model again")
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

    func testAFlaggedSentenceGetsAConfidentPointerAndCleanOnesAreNeverAsked() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["Yesterday I goes to the gym.", "They was there."]
        client.pointers = ["Yesterday I goes to the gym.": WordPointer(text: "goes", start: 12, end: 16, probability: 0.9, type: "tense", typeProbability: 0.97),
                           "They was there.": WordPointer(text: "there", start: 9, end: 14, probability: 0.3, type: "agreement", typeProbability: 0.9)]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "Yesterday I goes to the gym. They was there. It was fun.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map(\.pointer?.text), ["goes", nil, nil], "the unsure pointer is dropped")
        XCTAssertEqual(analyzer.sentences.first?.pointer?.type, "tense")
        XCTAssertEqual(client.locateRequests.flatMap { $0 }, ["Yesterday I goes to the gym.", "They was there."])
    }

    func testAnUnsureTypeIsDroppedButTheWordIsKept() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["She go to school."]
        client.pointers = ["She go to school.": WordPointer(text: "go", start: 4, end: 6, probability: 0.95, type: "tense", typeProbability: 0.4)]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "She go to school.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.first?.pointer?.text, "go")
        XCTAssertNil(analyzer.sentences.first?.pointer?.type, "never guess the kind of mistake")
    }

    func testALineBreakAlwaysEndsASentence() {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)
        let text = "Dear Sir/Madam\n\nThe Circle Theatre manager\nI am writing to complain. It was late."

        analyzer.update(text: text)

        XCTAssertEqual(analyzer.sentences.map(\.text),
                       ["Dear Sir/Madam", "The Circle Theatre manager", "I am writing to complain.", "It was late."])
        XCTAssertEqual(analyzer.sentences.map { (text as NSString).substring(with: $0.range) },
                       analyzer.sentences.map(\.text), "ranges still point at each sentence in the note")
    }

    func testHeadingsAndColonLinesNeedNoFullStop() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "Dear Sir/Madam\n\nIntroduction:\nHere is all the information you need:\nThe hotel is really lovely\nIs everything right")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) }, [
            [], [], [],
            [.missingEndPunctuation], // five words: a sentence, not a heading
            [.missingEndPunctuation], // the last line is never a heading
        ])
    }

    func testALineBecomesAHeadingOnceMoreTextFollowsIt() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "Dear Sir")
        await analyzer.idle()
        XCTAssertEqual(analyzer.sentences.first?.mechanics?.map(\.kind), [.missingEndPunctuation])

        analyzer.update(text: "Dear Sir\nThanks for the notes.")
        await analyzer.idle()
        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) }, [[], []])
    }

    func testMechanicsFlagsCapitalizationAndPunctuation() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "hello how are you? Yesterday i went home. Is everything right")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) }, [
            [.lowercaseStart, .missingComma],
            [.lowercaseI],
            [.missingEndPunctuation],
        ])
        XCTAssertEqual(analyzer.summary.mechanicsIssues, 4)
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

    func testBritishAndAmericanSpellingsBothPass() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "My favourite programme realised its colour. My favorite program realized its color. The programe was great.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.filter { $0.kind == .spelling }.compactMap(\.word) },
                       [[], [], ["programe"]])
    }

    func testSpellingComesFromTheOpenWordListNotTheMac() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "We met Siobhan at the café on the 21st at 3pm, etc. NASA don’t mind. Sarah's recieved it. Isabel came too.")
        await analyzer.idle()

        let marked = analyzer.sentences.flatMap { $0.mechanics ?? [] }.filter { $0.kind == .spelling }.compactMap(\.word)
        XCTAssertEqual(marked, ["recieved"], "names, accents, 21st/3pm, etc., acronyms, curly apostrophes and possessives all pass")
    }

    func testGreetingWithoutACommaIsFlagged() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "hello how are you? Hi, all good. Thanks for the notes.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.kind) },
                       [[.lowercaseStart, .missingComma], [], []])
    }

    func testGreetingToSomeoneWithoutACommaIsFlagged() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "Hello bro how are you? Hi John, what's new? Hey how is it going?")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.mechanics?.map(\.message) },
                       [["Missing comma after “bro”"], [], ["Missing comma after “Hey”"]])
    }

    func testIssuesNameTheWordsInvolved() async {
        let analyzer = NoteAnalyzer(client: FakeSignalClient(), debounce: .zero)

        analyzer.update(text: "hello how are you? We saw the the lake.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.summary.mechanics.map(\.issue.message), [
            "“hello” should start with a capital letter",
            "Missing comma after “hello”",
            "“the the” repeats a word",
        ])
        XCTAssertEqual(analyzer.summary.mechanics.first?.sentence, "hello how are you?")
    }

    func testSummaryListsSentencesFlaggedForGrammar() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["He go home."]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "He go home. She went home.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.summary.grammarFlagged, ["He go home."])
    }

    func testCorrectnessIsTheAverageSentenceScore() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["He go home."]  // grammar mistake probability 0.9; clean sentences get 0.1
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "He go home. She went home")
        await analyzer.idle()

        // "He go home." = 100 × (1 − 0.9) = 10; "She went home" is judged correct (0.1 < 0.5), so
        // 100 − 10 for the missing full stop = 90. Average: 50%.
        XCTAssertEqual(analyzer.summary.correctness ?? -1, 0.5, accuracy: 0.001)
    }

    func testCorrectnessNeverGoesBelowZero() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["i has went to the the store"]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "i has went to the the store")
        await analyzer.idle()

        XCTAssertEqual(analyzer.summary.correctness, 0)
    }

    func testFlawlessWritingScoresFullCorrectness() async {
        // The trained model gives correct sentences a mistake probability around 0.3; below 0.5 costs nothing.
        let client = FakeSignalClient()
        client.script = ["She went home.": ["grammar": Signal(value: "no", distribution: ["yes": 0.3, "no": 0.7])]]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "She went home.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.summary.correctness, 1)
    }

    func testSummaryListsSentencesThatDontMakeSense() async {
        let client = FakeSignalClient()
        client.script = [
            "I love cats because of okay.": ["sense": Signal(value: "yes", distribution: ["yes": 0.8, "no": 0.2])],
            "I love cats.": ["sense": Signal(value: "no", distribution: ["yes": 0.1, "no": 0.9])],
        ]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "I love cats. I love cats because of okay.")
        await analyzer.idle()

        XCTAssertEqual(analyzer.summary.senseFlagged, ["I love cats because of okay."])
    }

    func testCheckFlowScoresEachSentenceAgainstTheOneBefore() async {
        let client = FakeSignalClient()
        client.flowBreaks = ["My cat loves tuna."]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)
        analyzer.update(text: "The report is due Friday. I will send a draft Thursday. My cat loves tuna.")
        await analyzer.idle()

        await analyzer.checkFlow()

        XCTAssertEqual(client.flowRequests.last?.map(\.previous),
                       ["The report is due Friday.", "I will send a draft Thursday."])
        XCTAssertNil(analyzer.sentences[0].flow)
        XCTAssertEqual(analyzer.sentences.dropFirst().map { $0.flow?.value }, ["no", "yes"])
        XCTAssertEqual(analyzer.summary.flowFlagged, ["My cat loves tuna."])
    }

    func testEditingASentenceClearsOnlyTheFlowThatDependsOnIt() async {
        let client = FakeSignalClient()
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)
        analyzer.update(text: "One. Two. Three.")
        await analyzer.idle()
        await analyzer.checkFlow()

        analyzer.update(text: "One. Two, edited. Three.")
        await analyzer.idle()

        // "Two, edited." is new, and "Three." now follows a different sentence: both need checking again.
        XCTAssertNil(analyzer.sentences[1].flow)
        XCTAssertNil(analyzer.sentences[2].flow)

        analyzer.update(text: "One. Two, edited. Three. Four.")
        await analyzer.checkFlow()
        analyzer.update(text: "One. Two, edited. Three. Four, changed.")
        await analyzer.idle()

        XCTAssertNotNil(analyzer.sentences[2].flow)  // "Three." still follows "Two, edited."
    }

    func testEachSentenceHasItsOwnCorrectnessMatchingTheNoteScore() async {
        let client = FakeSignalClient()
        client.grammarMistake = ["He go home."]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "He go home. She went home")
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.map { $0.correctness ?? -1 }, [0.1, 0.9].map { $0 }, accuracy: 0.001)
        XCTAssertEqual(analyzer.summary.correctness ?? -1, 0.5, accuracy: 0.001)
    }

    func testASentenceThatDoesntMakeSenseLosesCorrectnessLikeAGrammarMistake() async {
        let client = FakeSignalClient()
        client.script = [
            "I love cats because of okay.": [
                "grammar": Signal(value: "no", distribution: ["yes": 0.3, "no": 0.7]),
                "sense": Signal(value: "yes", distribution: ["yes": 0.8, "no": 0.2]),
            ],
            "He go home because of okay.": [
                "grammar": Signal(value: "yes", distribution: ["yes": 0.9, "no": 0.1]),
                "sense": Signal(value: "yes", distribution: ["yes": 0.8, "no": 0.2]),
            ],
        ]
        let analyzer = NoteAnalyzer(client: client, debounce: .zero)

        analyzer.update(text: "I love cats because of okay. He go home because of okay.")
        await analyzer.idle()

        // Sense alone costs its likelihood (0.8); with both problems only the larger one counts (0.9).
        XCTAssertEqual(analyzer.sentences.map { $0.correctness ?? -1 }, [0.2, 0.1], accuracy: 0.001)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
