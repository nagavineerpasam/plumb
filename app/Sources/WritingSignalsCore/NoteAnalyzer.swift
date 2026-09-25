import Foundation
import NaturalLanguage
import Observation

public struct AnalyzedSentence: Identifiable, Sendable, Equatable {
    public let id: String
    public let text: String
    /// Where the sentence sits in the note, as a UTF-16 range for the text view.
    public let range: NSRange
    public var signals: SentenceSignals?
}

/// Keeps a note's per-sentence signals current as the user types.
@MainActor @Observable
public final class NoteAnalyzer {
    public private(set) var sentences: [AnalyzedSentence] = []

    private let client: SignalClient
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var nextID = 0

    public init(client: SignalClient, debounce: Duration = .milliseconds(300)) {
        self.client = client
        self.debounce = debounce
    }

    public func update(text: String) {
        sentences = Self.split(text).map { text, range in
            nextID += 1
            return AnalyzedSentence(id: "s\(nextID)", text: text, range: range, signals: nil)
        }
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.scoreUnscored()
        }
    }

    /// Waits until the analysis started by the latest update has finished.
    public func idle() async {
        await pending?.value
    }

    private func scoreUnscored() async {
        let requests = sentences.filter { $0.signals == nil }
            .map { SentenceRequest(id: $0.id, text: $0.text) }
        guard !requests.isEmpty, let results = try? await client.score(requests) else { return }
        for i in sentences.indices {
            if let signals = results[sentences[i].id] { sentences[i].signals = signals }
        }
    }

    static func split(_ text: String) -> [(String, NSRange)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let trimmed = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let start = text[range].firstIndex { !$0.isWhitespace && !$0.isNewline } ?? range.lowerBound
            let end = text.index(start, offsetBy: trimmed.count)
            return (trimmed, NSRange(start..<end, in: text))
        }
    }
}
