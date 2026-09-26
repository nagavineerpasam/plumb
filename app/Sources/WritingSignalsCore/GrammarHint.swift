import Foundation

/// What the card says about a grammar mistake. Plumb teaches: it says where the mistake is and what
/// kind of mistake it is, in the learner's own words, and never gives the answer. When the model
/// isn't sure it says less rather than guess.
public enum GrammarHint {
    public static let general = "Something in this sentence isn’t right. Try reading it aloud."

    /// The learner-facing name of each mistake type, for the "Needs a look" list.
    public static let names: [String: String] = [
        "tense": "Verb tense", "verb_form": "Verb form", "agreement": "Agreement",
        "article": "a / an / the", "article_missing": "a / an / the",
        "preposition": "Preposition", "preposition_missing": "Preposition", "number": "Singular or plural",
        "word_order": "Word order", "word_missing": "Missing word", "word_extra": "Extra word",
    ]

    public static func line(for sentence: String, pointer: WordPointer?) -> String {
        guard let pointer else { return general }
        let w = "“\(pointer.text)”"
        guard let type = pointer.type else { return "Check \(w)." }
        switch type {
        case "tense":
            return "Verb tense: check when this happened. Which form of \(w) fits?" + (timeWord(in: sentence).map { " “\($0)” tells you when." } ?? "")
        case "verb_form": return "Verb form: \(w) isn’t the right form of this verb here. Which form fits?"
        case "agreement": return "Agreement: \(w) doesn’t match the word it goes with. Check who or what it’s about."
        case "article": return "a / an / the: check \(w). Is it the right small word, and is it needed?"
        case "article_missing": return "a / an / the: a small word may be missing before \(w)."
        case "preposition": return "Preposition: \(w) isn’t the usual word here. Which small linking word fits?"
        case "preposition_missing": return "Preposition: a small linking word may be missing before \(w)."
        case "number": return "Singular or plural: check whether \(w) should be one or many."
        case "word_order": return "Word order: the words around \(w) are in an unusual order. Read it aloud to hear it."
        case "word_missing": return "Missing word: something is missing before \(w)."
        case "word_extra": return "Extra word: does \(w) need to be here?"
        default: return "Check \(w)."
        }
    }

    /// The short version for the "Needs a look" list.
    public static func short(for sentence: String, pointer: WordPointer?) -> String {
        guard let pointer else { return "Grammar mistake" }
        guard let name = pointer.type.flatMap({ names[$0] }) else { return "Check “\(pointer.text)”" }
        return "“\(pointer.text)” · \(name)"
    }

    /// A word that says when something happens ("Yesterday", "last week"), to anchor a tense hint.
    private static func timeWord(in sentence: String) -> String? {
        let pattern = #"\b(yesterday|tomorrow|tonight|\w+ ago|(last|next) (week|month|year|night|time|summer|winter|weekend))\b"#
        guard let r = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(sentence[r])
    }
}
