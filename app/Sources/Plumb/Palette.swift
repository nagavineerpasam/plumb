import SwiftUI

/// How each signal is named, ordered and coloured across the editor, cards and dashboard.
enum Palette {
    /// Off until a fine-tuned model passes the grammar accuracy bar (ticket 05). The base model
    /// flagged 0 of 30 broken test sentences, so showing its verdict would teach wrong things.
    static let grammarReady = false

    static var order: [String] {
        (grammarReady ? ["grammar"] : []) + ["tone", "emotion", "confidence", "clarity", "formality"]
    }

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

    /// Five words along each scale, low to high. Card and panel both use these.
    static let scaleWords = [
        "confidence": ["Hesitant", "Somewhat hesitant", "Balanced", "Fairly assertive", "Assertive"],
        "clarity": ["Confusing", "Somewhat unclear", "Fairly clear", "Clear", "Very clear"],
        "formality": ["Informal", "Somewhat informal", "Neutral", "Fairly formal", "Formal"],
    ]

    static func word(for scale: String, at position: Double) -> String {
        let words = scaleWords[scale] ?? []
        guard !words.isEmpty else { return "" }
        return words[min(words.count - 1, max(0, Int(position * Double(words.count))))]
    }

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
