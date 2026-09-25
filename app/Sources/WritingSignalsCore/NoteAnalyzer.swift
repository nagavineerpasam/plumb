import Foundation
import NaturalLanguage
import Observation

public struct AnalyzedSentence: Identifiable, Sendable, Equatable {
    public let id: String
    public let text: String
    /// Where the sentence sits in the note, as a UTF-16 range for the text view.
    public let range: NSRange
    public var signals: SentenceSignals?
    /// Capitalization and punctuation slips; nil until the typing pause.
    public var mechanics: [MechanicsIssue]?
    /// Whether this sentence fails to follow the one before it; nil until flow is checked.
    public var flow: Signal?
    /// The sentence this flow result was judged against; a different neighbour voids it.
    var flowPreviousID: String?

    /// How well this sentence is written, 0...1, once checked: 100% minus the likelihood of a
    /// grammar mistake or of not making sense, whichever is judged likely and larger (p >= 0.5;
    /// the trained model puts correct sentences near 0.3), minus 10 points per spelling or
    /// punctuation slip. The note's Correctness is the average of these.
    public var correctness: Double? {
        guard let grammar = signals?.signals["grammar"]?.distribution["yes"] else { return nil }
        let sense = signals?.signals["sense"]?.distribution["yes"] ?? 0
        // Only a judged problem (p >= 0.5) costs points, and one sentence isn't charged twice:
        // the larger of a grammar mistake and not making sense counts.
        let problem = max(grammar >= 0.5 ? grammar : 0, sense >= 0.5 ? sense : 0)
        return max(0, 1 - problem - 0.1 * Double(mechanics?.count ?? 0))
    }
}

/// Keeps a note's per-sentence signals current as the user types.
@MainActor @Observable
public final class NoteAnalyzer {
    public private(set) var sentences: [AnalyzedSentence] = []

    public var summary: NoteSummary { NoteSummary(sentences) }

    private let client: SignalClient
    private let debounce: Duration
    private let retryDelay: Duration
    private var pending: Task<Void, Never>?
    private var nextID = 0
    /// Results already worked out this session, by sentence text, so reopening a note shows its
    /// signals at once instead of checking unchanged sentences again.
    private var known: [String: (signals: SentenceSignals?, mechanics: [MechanicsIssue]?)] = [:]

    public init(client: SignalClient, debounce: Duration = .milliseconds(300),
                retryDelay: Duration = .seconds(1)) {
        self.client = client
        self.debounce = debounce
        self.retryDelay = retryDelay
    }

    public func update(text: String) {
        // Unchanged sentences keep their id and signals, so only edited ones are re-scored.
        var previous = Dictionary(grouping: sentences, by: \.text)
        sentences = Self.split(text).map { text, range in
            if let kept = previous[text]?.first {
                previous[text]?.removeFirst()
                return AnalyzedSentence(id: kept.id, text: text, range: range, signals: kept.signals,
                                        mechanics: kept.mechanics, flow: kept.flow, flowPreviousID: kept.flowPreviousID)
            }
            nextID += 1
            return AnalyzedSentence(id: "s\(nextID)", text: text, range: range,
                                    signals: known[text]?.signals, mechanics: known[text]?.mechanics)
        }
        // A flow result only holds while the sentence before it is the same one.
        for i in sentences.indices where sentences[i].flow != nil {
            if i == 0 || sentences[i].flowPreviousID != sentences[i - 1].id {
                sentences[i].flow = nil
                sentences[i].flowPreviousID = nil
            }
        }
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.checkMechanics()
            await self.scoreUnscored()
        }
    }

    /// Checks, on request, whether each sentence follows the one before it. Only pairs without a
    /// current result are sent; results for pairs that changed meanwhile are dropped.
    public func checkFlow() async {
        let pairs = sentences.indices.dropFirst().filter { sentences[$0].flow == nil }.map {
            (FlowRequest(id: sentences[$0].id, previous: sentences[$0 - 1].text, sentence: sentences[$0].text),
             sentences[$0 - 1].id)
        }
        guard !pairs.isEmpty, let results = try? await client.flow(pairs.map(\.0)) else { return }
        for (request, previousID) in pairs {
            guard let signal = results[request.id],
                  let i = sentences.firstIndex(where: { $0.id == request.id }),
                  i > 0, sentences[i - 1].id == previousID else { continue }
            sentences[i].flow = signal
            sentences[i].flowPreviousID = previousID
        }
    }

    /// Waits until the analysis started by the latest update has finished.
    public func idle() async {
        await pending?.value
    }

    private func checkMechanics() {
        for i in sentences.indices where sentences[i].mechanics == nil {
            // Splitting uses the raw text, so extra spaces survive into the sentence's range.
            sentences[i].mechanics = Mechanics.check(sentences[i].text)
            known[sentences[i].text, default: (nil, nil)].mechanics = sentences[i].mechanics
        }
    }

    /// Scores every sentence still without signals. If the worker is down (crashed and
    /// restarting), keeps retrying until it answers or a newer edit takes over.
    private func scoreUnscored() async {
        while !Task.isCancelled {
            let requests = sentences.filter { $0.signals == nil }
                .map { SentenceRequest(id: $0.id, text: $0.text) }
            guard !requests.isEmpty else { return }
            do {
                let results = try await client.score(requests)
                for i in sentences.indices {
                    if let signals = results[sentences[i].id] {
                        sentences[i].signals = signals
                        known[sentences[i].text, default: (nil, nil)].signals = signals
                    }
                }
                return
            } catch {
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    static func split(_ text: String) -> [(String, NSRange)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        // Knowing the language lets it keep abbreviations like "z. B." inside a sentence.
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            tokenizer.setLanguage(language)
        }
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let trimmed = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let start = text[range].firstIndex { !$0.isWhitespace && !$0.isNewline } ?? range.lowerBound
            let end = text.index(start, offsetBy: trimmed.count)
            return (trimmed, NSRange(start..<end, in: text))
        }
    }
}
