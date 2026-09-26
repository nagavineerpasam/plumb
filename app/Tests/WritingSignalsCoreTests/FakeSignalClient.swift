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
    /// Sentences that don't follow from the one before them.
    var flowBreaks: Set<String> = []
    private(set) var flowRequests: [[FlowRequest]] = []

    /// Which signals each score call asked for (nil = all).
    private(set) var requestedSignals: [[String]?] = []

    func score(_ sentences: [SentenceRequest], signals: [String]?) async throws -> [String: SentenceSignals] {
        requests.append(sentences.map(\.text))
        requestedSignals.append(signals)
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
            let all = script[s.text] ?? [
                "grammar": Signal(value: wrong ? "yes" : "no",
                                  distribution: ["yes": wrong ? 0.9 : 0.1, "no": wrong ? 0.1 : 0.9]),
                "tone": Signal(value: "neutral", distribution: ["neutral": 1]),
            ]
            out[s.id] = SentenceSignals(model: "english", signals: signals.map { names in all.filter { names.contains($0.key) } } ?? all)
        }
        return out
    }

    /// The word each sentence's "which word?" answer points at, by sentence text.
    var pointers: [String: WordPointer] = [:]
    private(set) var locateRequests: [[String]] = []

    func locate(_ sentences: [SentenceRequest]) async throws -> [String: WordPointer?] {
        locateRequests.append(sentences.map(\.text))
        return Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, pointers[$0.text]) })
    }

    func flow(_ pairs: [FlowRequest]) async throws -> [String: Signal] {
        flowRequests.append(pairs)
        var out: [String: Signal] = [:]
        for p in pairs {
            let broken = flowBreaks.contains(p.sentence)
            out[p.id] = Signal(value: broken ? "yes" : "no", distribution: ["yes": broken ? 0.8 : 0.2, "no": broken ? 0.2 : 0.8])
        }
        return out
    }
}
