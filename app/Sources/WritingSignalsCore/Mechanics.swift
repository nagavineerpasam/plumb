import AppKit

/// A capitalization or punctuation slip found by exact rules, no model involved.
public struct MechanicsIssue: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case spelling, lowercaseStart, lowercaseI, missingEndPunctuation, repeatedWord, extraSpace
    }

    public let kind: Kind
    /// For spelling: the misspelled word and where it sits in the sentence (UTF-16).
    public var word: String?
    public var range: NSRange?

    init(_ kind: Kind, word: String? = nil, range: NSRange? = nil) {
        self.kind = kind
        self.word = word
        self.range = range
    }

    public var message: String {
        switch kind {
        case .spelling: "Spelling: \(word ?? "")"
        case .lowercaseStart: "Start the sentence with a capital letter"
        case .lowercaseI: "Write “I” as a capital letter"
        case .missingEndPunctuation: "End the sentence with . ? or !"
        case .repeatedWord: "A word is repeated"
        case .extraSpace: "There is an extra space"
        }
    }
}

enum Mechanics {
    private static let closers = CharacterSet(charactersIn: "\"'”’)]»")
    private static let loneI = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}'’.])i(?=\s|[,;:!?'’]|$|\.(?!\p{L}))"#)
    // "that that" and "had had" are often correct English, so they are not flagged.
    private static let repeated = try! NSRegularExpression(
        pattern: #"\b(?!that\b|had\b)(\p{L}+)\s+\1\b"#, options: [.caseInsensitive])

    /// Misspelled words from the built-in macOS spell checker. Words only; no suggestions.
    @MainActor
    static func misspellings(in sentence: String) -> [MechanicsIssue] {
        let checker = NSSpellChecker.shared
        let text = sentence as NSString
        var issues: [MechanicsIssue] = []
        var start = 0
        while start < text.length {
            let found = checker.checkSpelling(of: sentence, startingAt: start, language: "en",
                                              wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            guard found.location != NSNotFound, found.length > 0 else { break }
            issues.append(MechanicsIssue(.spelling, word: text.substring(with: found), range: found))
            start = NSMaxRange(found)
        }
        return issues
    }

    @MainActor
    static func check(_ sentence: String) -> [MechanicsIssue] {
        misspellings(in: sentence) + rules(sentence)
    }

    static func rules(_ sentence: String) -> [MechanicsIssue] {
        var kinds: [MechanicsIssue.Kind] = []
        let whole = NSRange(sentence.startIndex..., in: sentence)
        if let first = sentence.first(where: { !$0.isPunctuation && !$0.isWhitespace }), first.isLowercase {
            kinds.append(.lowercaseStart)
        }
        // A sentence opening with "i" is already flagged as a lowercase start.
        let lowercaseIs = loneI.matches(in: sentence, range: whole)
            .filter { !(kinds.contains(.lowercaseStart) && $0.range.location == 0) }
        if !lowercaseIs.isEmpty { kinds.append(.lowercaseI) }
        let body = sentence.trimmingCharacters(in: closers.union(.whitespaces))
        if let last = body.last, !".!?…".contains(last) {
            kinds.append(.missingEndPunctuation)
        }
        if repeated.firstMatch(in: sentence, range: whole) != nil { kinds.append(.repeatedWord) }
        if sentence.contains("  ") { kinds.append(.extraSpace) }
        return kinds.map { MechanicsIssue($0) }
    }
}
