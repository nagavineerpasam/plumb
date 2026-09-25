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

    init(_ scored: [SentenceSignals]) {
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
