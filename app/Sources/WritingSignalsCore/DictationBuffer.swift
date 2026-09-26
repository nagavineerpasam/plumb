import Foundation

/// Turns speech-recognizer output into edits at the cursor, the way typing would. It never
/// holds the note's text: the editor applies each `Edit` to the text view. It tracks where the
/// dictation goes, which words are still in progress (shown grey), and which words the
/// recognizer was unsure of (hints), keeping those ranges right as the user edits around them.
public struct DictationBuffer: Sendable {
    public struct Edit: Sendable, Equatable {
        public let range: NSRange
        public let replacement: String
    }

    /// Where the next phrase goes.
    private var anchor: Int
    /// Characters of a selection still to be replaced by the first phrase.
    private var pendingSelection: Int
    /// Length of the in-progress text currently in the note, including any leading space.
    private var volatileLength = 0
    private var needsSpaceBefore: Bool
    /// In-progress words, shown grey. Nil when nothing is in progress.
    public private(set) var grey: NSRange?
    /// Whether any dictated words are in the note right now, settled or still grey.
    public var showsWords: Bool { settledLength > 0 || volatileLength > 0 }
    private var settledLength = 0
    /// Words the recognizer was unsure of, in note coordinates.
    public private(set) var hints: [NSRange] = []

    /// `keeping` carries hints from an earlier dictation in the same note.
    public init(selection: NSRange, in text: String, keeping hints: [NSRange] = []) {
        self.hints = hints
        anchor = selection.location
        pendingSelection = selection.length
        let before = selection.location > 0
            ? (text as NSString).character(at: selection.location - 1) : nil
        needsSpaceBefore = before.map { !(Character(UnicodeScalar($0) ?? " ").isWhitespace) } ?? false
    }

    /// The recognizer's current guess for the phrase being spoken; replaces the previous guess.
    public mutating func volatile(_ words: String) -> Edit {
        let edit = replaceInProgress(with: words)
        volatileLength = (edit.replacement as NSString).length
        let lead = edit.replacement.hasPrefix(" ") ? 1 : 0
        grey = NSRange(location: anchor + lead, length: volatileLength - lead)
        return edit
    }

    /// The finished phrase. `unsure` holds ranges within `phrase` heard with low confidence.
    public mutating func final(_ phrase: String, unsure: [NSRange]) -> Edit {
        let edit = replaceInProgress(with: phrase)
        let inserted = (edit.replacement as NSString).length
        let lead = edit.replacement.hasPrefix(" ") ? 1 : 0
        hints += unsure.map { NSRange(location: anchor + lead + $0.location, length: $0.length) }
        anchor += inserted
        settledLength += inserted
        volatileLength = 0
        grey = nil
        needsSpaceBefore = !(edit.replacement.last?.isWhitespace ?? true)
        return edit
    }

    /// The user changed `range` of the note to text of `replacementLength` characters. Hints
    /// after the change move with it; a hint the change touches is dropped.
    public mutating func userEdited(_ range: NSRange, replacementLength: Int) {
        let delta = replacementLength - range.length
        hints = hints.compactMap { hint in
            if NSMaxRange(range) <= hint.location {  // entirely before the word: move with it
                return NSRange(location: hint.location + delta, length: hint.length)
            }
            if range.location >= NSMaxRange(hint) { return hint }  // entirely after: unchanged
            return nil  // touches the word: the hint no longer applies
        }
        if range.location < anchor { anchor = max(range.location, anchor + delta) }
    }

    private mutating func replaceInProgress(with words: String) -> Edit {
        let text = needsSpaceBefore && !words.isEmpty ? " " + words : words
        let edit = Edit(range: NSRange(location: anchor, length: volatileLength + pendingSelection), replacement: text)
        pendingSelection = 0
        return edit
    }
}
