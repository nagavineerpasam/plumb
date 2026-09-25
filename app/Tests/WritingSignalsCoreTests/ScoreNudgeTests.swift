import XCTest
import WritingSignalsCore

final class ScoreNudgeTests: XCTestCase {
    func testTheFirstScoredChatInvitesYouToBeatIt() {
        XCTAssertEqual(ScoreNudge.message(score: 0.6, previous: nil), "You scored 60. Start a new chat and beat it.")
    }

    func testAHigherScoreCelebrates() {
        XCTAssertEqual(ScoreNudge.message(score: 0.72, previous: 0.6), "You scored 72 🎉 Up from 60 last time.")
    }

    func testTheSameOrALowerScoreEncouragesAnotherTry() {
        XCTAssertEqual(ScoreNudge.message(score: 0.55, previous: 0.6), "You scored 55. Last time was 60. Check the marks, then try again.")
        XCTAssertEqual(ScoreNudge.message(score: 0.6, previous: 0.6), "You scored 60. Last time was 60. Check the marks, then try again.")
    }

    func testScoresAreRoundedLikeTheScoreTile() {
        XCTAssertEqual(ScoreNudge.message(score: 0.716, previous: 0.715), "You scored 72. Last time was 72. Check the marks, then try again.")
    }
}
