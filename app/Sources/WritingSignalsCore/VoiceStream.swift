import Foundation

/// A word as the speech recognizer heard it (with its leading space, if any) and how sure it was.
public struct HeardWord: Sendable, Equatable {
    public let text: String
    public let probability: Double

    public init(text: String, probability: Double) {
        self.text = text
        self.probability = probability
    }
}

/// Turns a streaming recognizer's updates into DictationBuffer edits. Every update repeats all the
/// segments confirmed so far plus the text still being heard: each newly confirmed segment settles
/// once (checked like typing), and the rest shows grey until it's confirmed.
public struct VoiceStream: Sendable {
    private let unsureBelow: Double
    /// How many confirmed segments are already in the note.
    private var delivered = 0
    /// The in-progress words currently shown grey.
    private var shown = ""

    public init(unsureBelow: Double) {
        self.unsureBelow = unsureBelow
    }

    public mutating func update(confirmed: [[HeardWord]], unconfirmed: String,
                                buffer: inout DictationBuffer) -> [DictationBuffer.Edit] {
        var edits: [DictationBuffer.Edit] = []
        for segment in confirmed.dropFirst(delivered) {
            delivered += 1
            let (phrase, unsure) = phrase(from: segment)
            guard !phrase.isEmpty else { continue }
            edits.append(buffer.final(phrase, unsure: unsure))  // replaces the grey words
            shown = ""
        }
        let words = unconfirmed.trimmingCharacters(in: .whitespaces)
        if words != shown {
            edits.append(buffer.volatile(words))
            shown = words
        }
        return edits
    }

    /// The segment as one phrase, and where its low-confidence words sit within it.
    private func phrase(from segment: [HeardWord]) -> (String, [NSRange]) {
        let joined = segment.map(\.text).joined()
        let lead = joined.prefix { $0.isWhitespace }.utf16.count
        var unsure: [NSRange] = []
        var offset = 0
        for word in segment {
            let length = word.text.utf16.count
            if word.probability < unsureBelow {
                // Hint the word itself, not the space or punctuation around it.
                let core = word.text.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                if let range = word.text.range(of: core), !core.isEmpty {
                    let start = word.text.utf16.distance(from: word.text.startIndex, to: range.lowerBound)
                    unsure.append(NSRange(location: offset + start - lead, length: core.utf16.count))
                }
            }
            offset += length
        }
        return (joined.trimmingCharacters(in: .whitespaces), unsure)
    }
}
