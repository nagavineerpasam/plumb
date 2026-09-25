import AppKit

/// Where a grammar mistake is in a sentence, what's wrong, and fixes known to work.
public struct GrammarDetail: Sendable, Equatable {
    /// The word(s) at fault, as a UTF-16 range within the sentence.
    public let range: NSRange
    /// A short, plain explanation, e.g. “is” doesn’t agree with the rest of the sentence.
    public let message: String
    /// Replacements for the word that make the sentence pass the check (may be empty).
    public let fixes: [String]
}

/// Explains a sentence Laya has flagged: Laya knows *that* a sentence is wrong, macOS's built-in
/// grammar checker can often say *where*. Only used to explain Laya's flags, never to add new ones.
public enum GrammarExplainer {
    /// Nil when the checker finds nothing to point at. The spell checker belongs to the main thread.
    @MainActor
    public static func explain(_ sentence: String) -> GrammarDetail? {
        guard let (range, suggestions) = firstIssue(in: sentence) else { return nil }
        let word = (sentence as NSString).substring(with: range)
        // The checker offers every form of the word ("is" → "am", "are"); keep only the ones that
        // actually fix this sentence.
        let fixes = suggestions.filter { fix in
            firstIssue(in: (sentence as NSString).replacingCharacters(in: range, with: fix)) == nil
        }
        return GrammarDetail(range: range, message: "“\(word)” doesn’t agree with the rest of the sentence.", fixes: fixes)
    }

    @MainActor
    private static func firstIssue(in text: String) -> (NSRange, [String])? {
        var details: NSArray?
        let found = NSSpellChecker.shared.checkGrammar(of: text, startingAt: 0, language: "en", wrap: false,
                                                       inSpellDocumentWithTag: 0, details: &details)
        guard found.location != NSNotFound,
              let first = (details as? [[String: Any]])?.first,
              let range = (first[NSGrammarRange] as? NSValue)?.rangeValue, range.length > 0 else { return nil }
        return (range, first[NSGrammarCorrections] as? [String] ?? [])
    }
}
