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

/// Scores sentences. The real one talks to the signal worker; tests use a fake.
public protocol SignalClient: Sendable {
    /// Returns signals keyed by sentence id. Sentences superseded by a newer request may be missing.
    func score(_ sentences: [SentenceRequest]) async throws -> [String: SentenceSignals]
}
