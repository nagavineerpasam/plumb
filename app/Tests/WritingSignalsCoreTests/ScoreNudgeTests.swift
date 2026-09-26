import XCTest
import WritingSignalsCore

final class ScoreNudgeTests: XCTestCase {
    func testTheFirstScoredChatInvitesYouToBeatIt() {
        XCTAssertEqual(ScoreNudge.message(score: 0.6, previous: nil), "You scored 60. Start a new chat and beat it! 💪")
    }

    func testAPerfectScoreIsCelebratedNotChallenged() {
        XCTAssertEqual(ScoreNudge.message(score: 1.0, previous: nil), "🎉 A perfect 100! Keep it up with a new chat.")
        XCTAssertEqual(ScoreNudge.message(score: 1.0, previous: 1.0), "🎉 A perfect 100! Keep it up with a new chat.")
    }

    func testAHigherScoreCelebrates() {
        XCTAssertEqual(ScoreNudge.message(score: 0.72, previous: 0.6), "🎉 You scored 72, better than last time (60)! Keep it up with a new chat.")
    }

    func testTheSameOrALowerScoreMotivatesAnotherGo() {
        XCTAssertEqual(ScoreNudge.message(score: 0.55, previous: 0.6), "You scored 55. Start a new chat and aim higher! 💪")
        XCTAssertEqual(ScoreNudge.message(score: 0.6, previous: 0.6), "You scored 60. Start a new chat and aim higher! 💪")
    }

    func testScoresAreRoundedLikeTheScoreTile() {
        XCTAssertEqual(ScoreNudge.message(score: 0.716, previous: 0.715), "You scored 72. Start a new chat and aim higher! 💪")
    }
}
