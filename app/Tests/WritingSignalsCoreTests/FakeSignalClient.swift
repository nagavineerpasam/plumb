import WritingSignalsCore

/// Stands in for the signal worker: answers from a script keyed by sentence text.
final class FakeSignalClient: SignalClient, @unchecked Sendable {
    var grammarMistake: Set<String> = []
    private(set) var requests: [[String]] = []

    func score(_ sentences: [SentenceRequest]) async throws -> [String: SentenceSignals] {
        requests.append(sentences.map(\.text))
        var out: [String: SentenceSignals] = [:]
        for s in sentences {
            let wrong = grammarMistake.contains(s.text)
            out[s.id] = SentenceSignals(model: "english", signals: [
                "grammar": Signal(value: wrong ? "yes" : "no",
                                  distribution: ["yes": wrong ? 0.9 : 0.1, "no": wrong ? 0.1 : 0.9]),
            ])
        }
        return out
    }
}
