import Foundation

/// What the card says about a grammar mistake: the word the model points at (with macOS's fix
/// when macOS suggests one for that same word), else macOS's own detail, else a general hint.
public enum GrammarHint {
    public static let general = "Something in this sentence isn’t quite right. Try reading it aloud, and check the verb forms and word order."

    public static func line(for sentence: String, pointer: WordPointer?, macOS: GrammarDetail?) -> String {
        if let pointer {
            return "“\(pointer.text)” looks wrong here." + (fix(for: pointer, macOS).map { " Try “\($0)”." } ?? "")
        }
        guard let macOS else { return general }
        return macOS.fixes.first.map { macOS.message + " Try “\($0)”." } ?? macOS.message
    }

    /// The short version for the "Needs a look" list.
    public static func short(for sentence: String, pointer: WordPointer?, macOS: GrammarDetail?) -> String {
        if let pointer {
            return fix(for: pointer, macOS).map { "“\(pointer.text)” → “\($0)”" } ?? "Check “\(pointer.text)”"
        }
        guard let macOS else { return "Grammar mistake" }
        let word = (sentence as NSString).substring(with: macOS.range)
        return macOS.fixes.first.map { "“\(word)” → “\($0)”" } ?? "Check “\(word)”"
    }

    /// macOS's fix, only when it's about the word the model points at.
    private static func fix(for pointer: WordPointer, _ macOS: GrammarDetail?) -> String? {
        guard let macOS, NSIntersectionRange(macOS.range, pointer.range).length > 0 else { return nil }
        return macOS.fixes.first
    }
}
