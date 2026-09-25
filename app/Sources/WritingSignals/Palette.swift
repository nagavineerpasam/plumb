import SwiftUI

/// How each signal is named, ordered and coloured across the editor, cards and dashboard.
enum Palette {
    static let order = ["grammar", "tone", "emotion", "confidence", "clarity", "formality"]

    static let titles = [
        "grammar": "Grammar", "tone": "Tone", "emotion": "Emotion",
        "confidence": "Confidence", "clarity": "Clarity", "formality": "Formality",
    ]

    /// Low and high ends of the score signals.
    static let scales = [
        "confidence": ("Hesitant", "Assertive"),
        "clarity": ("Confusing", "Clear"),
        "formality": ("Informal", "Formal"),
    ]

    static let emotions: [String: Color] = [
        "joy": .yellow, "anger": .red, "sadness": .blue,
        "fear": .purple, "surprise": .orange, "neutral": .gray,
    ]

    static let tones: [String: Color] = [
        "formal": .indigo, "neutral": .gray, "casual": .teal, "friendly": .pink,
    ]

    static func color(signal: String, value: String) -> Color {
        switch signal {
        case "emotion": emotions[value] ?? .gray
        case "tone": tones[value] ?? .gray
        case "grammar": value == "yes" ? .red : .green
        default: .accentColor
        }
    }
}
