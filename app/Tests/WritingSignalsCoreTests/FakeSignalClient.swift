import WritingSignalsCore

/// Stands in for the signal worker: answers from a script keyed by sentence text.
final class FakeSignalClient: SignalClient, @unchecked Sendable {
    /// Signals per sentence text; unscripted sentences get a clean grammar signal only.
    var script: [String: [String: Signal]] = [:]
    var grammarMistake: Set<String> = []
    /// Number of upcoming calls that fail as if the worker had crashed.
    var failures = 0
    /// When set, calls wait here until the test releases them.
    var gate: AsyncStream<Void>.Iterator?
    private(set) var requests: [[String]] = []

    func score(_ sentences: [SentenceRequest]) async throws -> [String: SentenceSignals] {
        requests.append(sentences.map(\.text))
        if failures > 0 {
            failures -= 1
            throw WorkerError.exited
        }
        if var gate {
            _ = await gate.next()
            self.gate = gate
        }
        var out: [String: SentenceSignals] = [:]
        for s in sentences {
            let wrong = grammarMistake.contains(s.text)
            out[s.id] = SentenceSignals(model: "english", signals: script[s.text] ?? [
                "grammar": Signal(value: wrong ? "yes" : "no",
                                  distribution: ["yes": wrong ? 0.9 : 0.1, "no": wrong ? 0.1 : 0.9]),
            ])
        }
        return out
    }
}
