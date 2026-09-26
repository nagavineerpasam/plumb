import XCTest
import WritingSignalsCore

final class VoiceStreamTests: XCTestCase {
    private func words(_ spoken: String, unsure: Set<String> = []) -> [HeardWord] {
        spoken.split(separator: " ").map { word in
            HeardWord(text: " " + word, probability: unsure.contains(String(word)) ? 0.2 : 0.95)
        }
    }

    /// Feeds one streaming update and applies its edits to `text`, the way the editor would.
    private func feed(_ stream: inout VoiceStream, _ buffer: inout DictationBuffer, _ text: inout String,
                      confirmed: [[HeardWord]], unconfirmed: String) -> Int {
        let edits = stream.update(confirmed: confirmed, unconfirmed: unconfirmed, buffer: &buffer)
        for edit in edits {
            let ns = NSMutableString(string: text)
            ns.replaceCharacters(in: edit.range, with: edit.replacement)
            text = ns as String
        }
        return edits.count
    }

    func testWordsStillBeingHeardShowGrey() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)
        var stream = VoiceStream(unsureBelow: 0.35)

        _ = feed(&stream, &buffer, &text, confirmed: [], unconfirmed: " Yesterday I")

        XCTAssertEqual(text, "Yesterday I")
        XCTAssertEqual((text as NSString).substring(with: buffer.grey!), "Yesterday I")
    }

    func testAConfirmedSegmentSettlesExactlyOnce() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)
        var stream = VoiceStream(unsureBelow: 0.35)
        let first = words("Yesterday I goes to the gym.")

        _ = feed(&stream, &buffer, &text, confirmed: [], unconfirmed: " Yesterday I goes")
        _ = feed(&stream, &buffer, &text, confirmed: [first], unconfirmed: "")
        XCTAssertEqual(text, "Yesterday I goes to the gym.")
        XCTAssertNil(buffer.grey)

        // WhisperKit repeats confirmed segments in every later update.
        XCTAssertEqual(feed(&stream, &buffer, &text, confirmed: [first], unconfirmed: ""), 0)
        _ = feed(&stream, &buffer, &text, confirmed: [first, words("It was fun.")], unconfirmed: " Then we")

        XCTAssertEqual(text, "Yesterday I goes to the gym. It was fun. Then we")
        XCTAssertEqual((text as NSString).substring(with: buffer.grey!), "Then we")
    }

    func testWordsHeardWithLowConfidenceBecomeHints() {
        var text = "Note: "
        var buffer = DictationBuffer(selection: NSRange(location: 6, length: 0), in: text)
        var stream = VoiceStream(unsureBelow: 0.35)

        _ = feed(&stream, &buffer, &text, confirmed: [words("We met Siobhan at noon.", unsure: ["Siobhan"])], unconfirmed: "")

        XCTAssertEqual(text, "Note: We met Siobhan at noon.")
        XCTAssertEqual(buffer.hints.map { (text as NSString).substring(with: $0) }, ["Siobhan"])
    }

    func testWhispersSoundTagsNeverReachTheNote() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)
        var stream = VoiceStream(unsureBelow: 0.35)

        // Silence and noise come back as tags, sometimes split into several "words".
        XCTAssertEqual(feed(&stream, &buffer, &text, confirmed: [[HeardWord(text: " [BLANK_AUDIO]", probability: 0.9)]], unconfirmed: " [ Silence ]"), 0)
        _ = feed(&stream, &buffer, &text,
                 confirmed: [[HeardWord(text: " [BLANK_AUDIO]", probability: 0.9)],
                             [HeardWord(text: " [", probability: 0.9), HeardWord(text: "Silence", probability: 0.9),
                              HeardWord(text: " ]", probability: 0.9)] + words("I checked the numbers.")],
                 unconfirmed: " (music) The results")

        XCTAssertEqual(text, "I checked the numbers. The results")
        XCTAssertEqual((text as NSString).substring(with: buffer.grey!), "The results")
    }

    func testTagsAreRemovedButTheWordsAroundThemKept() {
        XCTAssertEqual(VoiceStream.withoutTags("[BLANK_AUDIO] Hello there"), " Hello there")
        XCTAssertEqual(VoiceStream.withoutTags("(music)"), "")
    }

    func testNothingNewMeansNoEdit() {
        var text = ""
        var buffer = DictationBuffer(selection: NSRange(location: 0, length: 0), in: text)
        var stream = VoiceStream(unsureBelow: 0.35)

        XCTAssertEqual(feed(&stream, &buffer, &text, confirmed: [], unconfirmed: ""), 0)
        _ = feed(&stream, &buffer, &text, confirmed: [], unconfirmed: " Hello")
        XCTAssertEqual(feed(&stream, &buffer, &text, confirmed: [], unconfirmed: " Hello"), 0)
        XCTAssertEqual(text, "Hello")
    }
}
