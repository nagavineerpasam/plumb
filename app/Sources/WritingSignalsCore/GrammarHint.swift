import Foundation

/// What the card says about a grammar mistake. Plumb teaches: it says where the mistake is and what
/// kind of mistake it is, in the learner's own words, and never gives the answer. When the model
/// isn't sure it says less rather than guess.
public enum GrammarHint {
    public static let general = "This sentence has a mistake. Read it again and try changing it."

    /// The learner-facing name of each mistake type, for the "Needs a look" list.
    public static let names: [String: String] = [
        "verb": "Verb", "agreement": "Agreement", "article": "a / an / the", "preposition": "Preposition",
        "number": "Singular or plural", "word_order": "Word order", "word_missing": "Missing word", "word_extra": "Extra word",
    ]

    public static func line(for sentence: String, pointer: WordPointer?) -> String {
        guard let pointer else { return general }
        let w = "“\(pointer.text)”"
        guard let type = pointer.type else { return "\(w) has a mistake here. Try changing it." }
        switch type {
        case "verb":
            return "Verb: check the tense and form of \(w). Which form fits here?" + (timeWord(in: sentence).map { " “\($0)” tells you when." } ?? "")
        case "agreement": return "Agreement: \(w) doesn’t match the word it goes with. Check who or what it’s about."
        case "article": return "a / an / the: check \(w). Is it the right small word, and is it needed?"
        case "preposition": return "Preposition: \(w) isn’t the usual word here. Which small linking word fits?"
        case "number": return "Singular or plural: check whether \(w) should be one or many."
        case "word_order": return "Word order: the words around \(w) are in an unusual order. Read it aloud to hear it."
        case "word_missing": return "Missing word: something is missing before \(w)."
        case "word_extra": return "Extra word: does \(w) need to be here?"
        default: return "\(w) has a mistake here. Try changing it."
        }
    }

    /// The short version for the "Needs a look" list.
    public static func short(for sentence: String, pointer: WordPointer?) -> String {
        guard let pointer else { return "Grammar mistake" }
        guard let name = pointer.type.flatMap({ names[$0] }) else { return "“\(pointer.text)” has a mistake" }
        return "“\(pointer.text)” · \(name)"
    }

    /// A word that says when something happens ("Yesterday", "last week"), to anchor a verb hint.
    private static func timeWord(in sentence: String) -> String? {
        let pattern = #"\b(yesterday|tomorrow|tonight|\w+ ago|(last|next) (week|month|year|night|time|summer|winter|weekend))\b"#
        guard let r = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(sentence[r])
    }
}
