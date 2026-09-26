/// One mechanics mistake and the sentence it was found in.
public struct MechanicsFinding: Sendable, Equatable {
    public let sentence: String
    public let issue: MechanicsIssue
}

/// The whole note at a glance, over sentences that have been scored.
public struct NoteSummary: Sendable, Equatable {
    public var scoredSentences = 0
    /// Share of sentences flagged as containing a grammatical mistake.
    public var grammarErrorRate: Double?
    /// Share of sentences per tone and per emotion value.
    public var tone: [String: Double] = [:]
    public var emotion: [String: Double] = [:]
    /// Mean 0...1 position on each scale.
    public var confidence: Double?
    public var clarity: Double?
    public var formality: Double?
    /// Every spelling, capitalization and punctuation mistake, in reading order.
    public var mechanics: [MechanicsFinding] = []
    public var mechanicsIssues: Int { mechanics.count }
    /// Sentences the grammar signal marks as likely containing a mistake.
    public var grammarFlagged: [String] = []
    /// Sentences the sense signal marks as not making sense as natural English.
    public var senseFlagged: [String] = []
    /// The word the model points at in grammar-flagged sentences, by sentence text.
    public var pointers: [String: WordPointer] = [:]
    /// Sentences that don't follow from the one before them (after a flow check).
    public var flowFlagged: [String] = []
    /// How well the note is written, 0...1: the average of each checked sentence's correctness.
    public var correctness: Double?

    init(_ sentences: [AnalyzedSentence]) {
        mechanics = sentences.flatMap { s in (s.mechanics ?? []).map { MechanicsFinding(sentence: s.text, issue: $0) } }
        grammarFlagged = sentences.filter { $0.signals?.signals["grammar"]?.value == "yes" }.map(\.text)
        senseFlagged = sentences.filter { $0.signals?.signals["sense"]?.value == "yes" }.map(\.text)
        pointers = Dictionary(sentences.compactMap { s in s.pointer.map { (s.text, $0) } }, uniquingKeysWith: { a, _ in a })
        flowFlagged = sentences.filter { $0.flow?.value == "yes" }.map(\.text)
        let judged = sentences.compactMap(\.correctness)
        if !judged.isEmpty { correctness = judged.reduce(0, +) / Double(judged.count) }
        let scored = sentences.compactMap(\.signals)
        guard !scored.isEmpty else { return }
        let n = Double(scored.count)
        scoredSentences = scored.count
        func share(_ name: String) -> [String: Double] {
            scored.compactMap { $0.signals[name]?.value }
                .reduce(into: [:]) { $0[$1, default: 0] += 1 / n }
        }
        func mean(_ name: String) -> Double? {
            let scores = scored.compactMap { $0.signals[name]?.score }
            return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        }
        grammarErrorRate = share("grammar")["yes"] ?? 0
        tone = share("tone")
        emotion = share("emotion")
        confidence = mean("confidence")
        clarity = mean("clarity")
        formality = mean("formality")
    }
}
