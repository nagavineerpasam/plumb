import XCTest
import WritingSignalsCore

/// Levels are microphone RMS per ~20 ms buffer, about 50 a second.
final class VoiceActivityTests: XCTestCase {
    private func feed(_ detector: inout VoiceActivity, _ level: Double, seconds: Double) -> [Bool] {
        (0..<Int(seconds * 50)).map { _ in detector.hears(level) }
    }

    func testSoftSpeechInAQuietRoomCountsAsVoice() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.002, seconds: 1)  // the room before you speak

        XCTAssertTrue(feed(&detector, 0.008, seconds: 0.5).allSatisfy { $0 })
    }

    func testASteadyNoisyRoomIsNotVoice() {
        var detector = VoiceActivity()

        XCTAssertFalse(feed(&detector, 0.02, seconds: 3).suffix(50).contains(true))
    }

    func testLoudSpeechCountsAsVoice() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.004, seconds: 1)

        XCTAssertTrue(feed(&detector, 0.06, seconds: 0.5).allSatisfy { $0 })
    }

    func testLongUnbrokenSpeechStaysVoice() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.002, seconds: 1)

        XCTAssertTrue(feed(&detector, 0.008, seconds: 12).suffix(50).allSatisfy { $0 }, "speech never becomes the new background")
    }

    func testTalkingTheMomentSpeakIsClickedStillCounts() {
        var detector = VoiceActivity()
        // Speech straight away, no quiet lead-in: loud syllables with the short gaps between words.
        let speech = (0..<150).map { $0 % 10 < 7 ? 0.012 : 0.003 }
        let heard = speech.map { detector.hears($0) }

        XCTAssertFalse(heard.prefix(25).contains(true), "while the room is measured only clearly loud sound counts (the audio itself is kept)")
        let syllables = zip(speech, heard).dropFirst(50).filter { $0.0 == 0.012 }
        XCTAssertTrue(syllables.allSatisfy { $0.1 }, "the floor settles on the gaps, not on the voice")
    }

    func testBackgroundNoiseWhileMeasuringIsNotVoice() {
        var detector = VoiceActivity()
        // A normal room is louder than a silent studio: its hum must not count as speech at the start.
        XCTAssertFalse(feed(&detector, 0.007, seconds: 2).contains(true))
    }

    func testClearlyLoudSpeechCountsEvenWhileMeasuring() {
        var detector = VoiceActivity()
        XCTAssertTrue(detector.hears(0.05))
    }

    func testAShortWordWhileMeasuringIsRecognisedOnceTheRoomIsKnown() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.002, seconds: 0.2)
        _ = feed(&detector, 0.01, seconds: 0.1)   // a quick "hi" at normal volume, while measuring
        XCTAssertNil(detector.sounds(0.01), "can't judge yet: the room is still being measured")
        _ = feed(&detector, 0.002, seconds: 0.3)

        XCTAssertEqual(detector.sounds(0.01), true, "looking back, that was speech")
        XCTAssertEqual(detector.sounds(0.002), false)
    }

    func testSilenceAfterSpeechIsNotVoice() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.002, seconds: 1)
        _ = feed(&detector, 0.03, seconds: 2)

        XCTAssertFalse(feed(&detector, 0.002, seconds: 1).suffix(25).contains(true))
    }
}
