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
                                        mechanics: kept.mechanics)
            }
            nextID += 1
            return AnalyzedSentence(id: "s\(nextID)", text: text, range: range)
        }
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.checkMechanics()
            await self.scoreUnscored()
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
                    if let signals = results[sentences[i].id] { sentences[i].signals = signals }
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
