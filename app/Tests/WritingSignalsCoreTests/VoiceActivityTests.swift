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

    func testSilenceAfterSpeechIsNotVoice() {
        var detector = VoiceActivity()
        _ = feed(&detector, 0.002, seconds: 1)
        _ = feed(&detector, 0.03, seconds: 2)

        XCTAssertFalse(feed(&detector, 0.002, seconds: 1).suffix(25).contains(true))
    }
}
