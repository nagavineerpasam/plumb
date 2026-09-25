import AppKit
import SwiftUI

/// How each signal is named, ordered and coloured across the editor, cards and dashboard.
/// A colour with separate light and dark values, resolved by the system appearance.
func adaptive(light: UInt32, dark: UInt32) -> Color {
    func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
    })
}

enum Palette {
    /// "Soft": a light grey canvas with white rounded cards (dark: charcoal on near-black).
    static let canvas = adaptive(light: 0xf6f7f9, dark: 0x191b20)
    static let card = adaptive(light: 0xffffff, dark: 0x23262c)

    /// On since the fine-tuned model passed its bar (CoLA 0.789 vs 0.75; 25 of 30 everyday
    /// mistakes caught with no false alarms). The base model flagged 0 of 30.
    static let grammarReady = true

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
