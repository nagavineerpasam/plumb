import Foundation

/// The short, friendly line at the bottom of a scored chat: a celebration when you beat your
/// previous chat, otherwise encouragement to start a new one and score higher. Scores are compared as shown (whole numbers).
public enum ScoreNudge {
    public static func message(score: Double, previous: Double?) -> String {
        let now = shown(score)
        if now == 100 { return "🎉 A perfect 100! Keep it up with a new chat." }  // nothing to beat
        guard let previous else { return "You scored \(now). Start a new chat and beat it! 💪" }
        let before = shown(previous)
        if now > before { return "🎉 You scored \(now), better than last time (\(before))! Keep it up with a new chat." }
        return "You scored \(now). Start a new chat and aim higher! 💪"
    }

    private static func shown(_ score: Double) -> Int { Int((score * 100).rounded()) }
}
