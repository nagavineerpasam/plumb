import Foundation

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

    /// Misspelled words, marked without suggestions. A word is wrong only if it's in neither the US
    /// nor the UK list; names (capitalised mid-sentence), acronyms and words glued to digits pass.
    static func misspellings(in sentence: String) -> [MechanicsIssue] {
        guard !englishWords.isEmpty else { return [] }  // a missing list must never mark every word
        let text = sentence as NSString
        var issues: [MechanicsIssue] = []
        for (i, match) in wordPattern.matches(in: sentence, range: NSRange(location: 0, length: text.length)).enumerated() {
            let word = text.substring(with: match.range)
            if i > 0, word.first?.isUppercase == true { continue }            // a name
            if word.count > 1, word == word.uppercased() { continue }         // an acronym, or shouting
            var key = word.lowercased().replacingOccurrences(of: "’", with: "'")
            if key.hasSuffix("'s") { key.removeLast(2) }                      // Sarah's
            if !englishWords.contains(key) { issues.append(MechanicsIssue(.spelling, word: word, range: match.range)) }
        }
        return issues
    }

    /// Letters, with inner apostrophes ("don't", "don’t"); never part of a number ("21st", "3pm").
    private static let wordPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])\p{L}(?:\p{L}|['’](?=\p{L}))*(?![\p{L}\p{N}_])"#)

    /// SCOWL's English words (open source, see SCOWL-Copyright.txt), loaded once. In the packaged
    /// app the list sits in Contents/Resources; `swift run` and tests use the package's bundle.
    static let englishWords: Set<String> = {
        let url = Bundle.main.bundlePath.hasSuffix(".app")
            ? Bundle.main.url(forResource: "english-words", withExtension: "txt")
            : Bundle.module.url(forResource: "english-words", withExtension: "txt")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }()

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
        // A line ending in a colon introduces what follows ("Introduction:"), so it needs no full stop.
        if let last = body.last, !".!?…:".contains(last) {
            issues.append(MechanicsIssue(.missingEndPunctuation))
        }
        if let match = repeated.firstMatch(in: sentence, range: whole) {
            issues.append(MechanicsIssue(.repeatedWord, word: text.substring(with: match.range)))
        }
        if sentence.contains("  ") { issues.append(MechanicsIssue(.extraSpace)) }
        return issues
    }
}
