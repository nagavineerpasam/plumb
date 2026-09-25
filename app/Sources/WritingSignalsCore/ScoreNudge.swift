import Foundation

/// The short, friendly line at the bottom of a scored chat: how you did, compared with your
/// previous chat, and an invitation to go again. Scores are compared as shown (whole numbers).
public enum ScoreNudge {
    public static func message(score: Double, previous: Double?) -> String {
        let now = shown(score)
        guard let previous else { return "You scored \(now). Start a new chat and beat it." }
        let before = shown(previous)
        if now > before { return "You scored \(now) 🎉 Up from \(before) last time." }
        return "You scored \(now). Last time was \(before). Check the marks, then try again."
    }

    private static func shown(_ score: Double) -> Int { Int((score * 100).rounded()) }
}
