import Foundation
/// One signal's answer for one sentence, as the worker sends it.
public struct Signal: Codable, Sendable, Equatable {
    public var value: String
    public var distribution: [String: Double]
    /// 0...1 position on the scale, only for score signals (formality, confidence, clarity).
    public var score: Double?

    public init(value: String, distribution: [String: Double], score: Double? = nil) {
        self.value = value
        self.distribution = distribution
        self.score = score
    }
}

public struct SentenceSignals: Codable, Sendable, Equatable {
    public var model: String
    public var signals: [String: Signal]

    public init(model: String, signals: [String: Signal]) {
        self.model = model
        self.signals = signals
    }
}

public struct SentenceRequest: Codable, Sendable, Equatable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// A sentence and the one before it, for the flow check.
public struct FlowRequest: Codable, Sendable, Equatable {
    public var id: String
    public var previous: String
    public var sentence: String

    public init(id: String, previous: String, sentence: String) {
        self.id = id
        self.previous = previous
        self.sentence = sentence
    }
}

/// The word the model thinks is wrong in a flagged sentence: its text, its UTF-16 offsets within
/// the sentence, and how sure the model is.
public struct WordPointer: Codable, Sendable, Equatable {
    public var text: String
    public var start: Int
    public var end: Int
    public var probability: Double

    public init(text: String, start: Int, end: Int, probability: Double) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }

    public var range: NSRange { NSRange(location: start, length: end - start) }
}

/// Scores sentences. The real one talks to the signal worker; tests use a fake.
public protocol SignalClient: Sendable {
    /// Returns signals keyed by sentence id. Sentences superseded by a newer request may be missing.
    func score(_ sentences: [SentenceRequest]) async throws -> [String: SentenceSignals]
    /// Returns, keyed by sentence id, whether each sentence fails to follow the one before it.
    func flow(_ pairs: [FlowRequest]) async throws -> [String: Signal]
    /// Returns, keyed by sentence id, the word most likely to be wrong (nil when the sentence is
    /// too long to point in).
    func locate(_ sentences: [SentenceRequest]) async throws -> [String: WordPointer?]
}
