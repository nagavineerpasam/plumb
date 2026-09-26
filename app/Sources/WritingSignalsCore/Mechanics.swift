import AppKit

/// A spelling, capitalization or punctuation mistake found by exact rules, no model involved.
public struct MechanicsIssue: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case spelling, lowercaseStart, lowercaseI, missingComma, missingEndPunctuation, repeatedWord, extraSpace
    }

    public let kind: Kind
    /// The word or words involved, and for spelling where they sit in the sentence (UTF-16).
    public var word: String?
    public var range: NSRange?

    init(_ kind: Kind, word: String? = nil, range: NSRange? = nil) {
        self.kind = kind
        self.word = word
        self.range = range
    }

    /// States the mistake plainly, naming the word, without offering a fix.
    public var message: String {
        let w = word ?? ""
        return switch kind {
        case .spelling: "“\(w)” is misspelled"
        case .lowercaseStart: "“\(w)” should start with a capital letter"
        case .lowercaseI: "“i” should be a capital “I”"
        case .missingComma: "Missing comma after “\(w)”"
        case .missingEndPunctuation: "Missing . ? or ! at the end"
        case .repeatedWord: "“\(w)” repeats a word"
        case .extraSpace: "Extra space between words"
        }
    }
}

enum Mechanics {
    private static let closers = CharacterSet(charactersIn: "\"'”’)]»")
    private static let firstWord = try! NSRegularExpression(pattern: #"\p{L}[\p{L}'’]*"#)
    private static let loneI = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}'’.])i(?=\s|[,;:!?'’]|$|\.(?!\p{L}))"#)
    // A greeting or interjection runs straight into a new clause: "hello how are you", "yes I can".
    private static let introWithoutComma = try! NSRegularExpression(
        // "Hello how are you", and also a greeting to someone: "Hello bro how are you" needs a comma
        // before "how". The word shown is the one the comma goes after.
        pattern: #"^\W*(hello|hi|hey|yes|well|ok|okay|oh)(?:\s+(?!(?:how|what|where|when|why|who|i|we|you|it|is|are|can|could|do|did|this|that|please|thanks|thank)\b)(\p{L}+))?\s+(?=(how|what|where|when|why|who|i|we|you|it|is|are|can|could|do|did|this|that|please|thanks|thank)\b)"#,
        options: [.caseInsensitive])
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
        let text = sentence as NSString
        let whole = NSRange(location: 0, length: text.length)
        var issues: [MechanicsIssue] = []

        let first = firstWord.firstMatch(in: sentence, range: whole)
        if let first, let letter = text.substring(with: first.range).first, letter.isLowercase,
           sentence.first(where: { !$0.isPunctuation && !$0.isWhitespace })?.isLetter == true {
            issues.append(MechanicsIssue(.lowercaseStart, word: text.substring(with: first.range)))
        }
        // A sentence opening with "i" is already flagged as a lowercase start.
        let lowercaseIs = loneI.matches(in: sentence, range: whole)
            .filter { !(issues.first?.kind == .lowercaseStart && $0.range.location == first?.range.location) }
        if !lowercaseIs.isEmpty { issues.append(MechanicsIssue(.lowercaseI, word: "i")) }
        if let intro = introWithoutComma.firstMatch(in: sentence, range: whole) {
            let before = intro.range(at: 2).location != NSNotFound ? intro.range(at: 2) : intro.range(at: 1)
            issues.append(MechanicsIssue(.missingComma, word: text.substring(with: before)))
        }
        let body = sentence.trimmingCharacters(in: closers.union(.whitespaces))
        if let last = body.last, !".!?…".contains(last) {
            issues.append(MechanicsIssue(.missingEndPunctuation))
        }
        if let match = repeated.firstMatch(in: sentence, range: whole) {
            issues.append(MechanicsIssue(.repeatedWord, word: text.substring(with: match.range)))
        }
        if sentence.contains("  ") { issues.append(MechanicsIssue(.extraSpace)) }
        return issues
    }
}
