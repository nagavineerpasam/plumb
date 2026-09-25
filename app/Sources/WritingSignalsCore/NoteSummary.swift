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
    /// How well the note is written, 0...1: each sentence starts at 100%, loses the likelihood of a
    /// grammar mistake when one is judged likely, and 10 points per spelling or punctuation slip;
    /// the note is the average.
    public var correctness: Double?

    init(_ sentences: [AnalyzedSentence]) {
        mechanics = sentences.flatMap { s in (s.mechanics ?? []).map { MechanicsFinding(sentence: s.text, issue: $0) } }
        grammarFlagged = sentences.filter { $0.signals?.signals["grammar"]?.value == "yes" }.map(\.text)
        let judged = sentences.compactMap { s -> Double? in
            guard let p = s.signals?.signals["grammar"]?.distribution["yes"] else { return nil }
            // Only a judged mistake (p >= 0.5) costs points: the trained model puts correct
            // sentences around 0.3, which should still count as fully correct.
            let mistake = p >= 0.5 ? p : 0
            return max(0, 1 - mistake - 0.1 * Double(s.mechanics?.count ?? 0))
        }
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
