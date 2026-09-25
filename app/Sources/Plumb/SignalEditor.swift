import AppKit
import SwiftUI
import WritingSignalsCore

/// TextKit 2 editor. Signals are drawn as rendering attributes, which never touch the text.
struct SignalEditor: NSViewRepresentable {
    let analyzer: NoteAnalyzer
    /// Changes whenever a different note is opened, so its text replaces the editor's.
    let noteID: URL?
    let initialText: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(analyzer: analyzer) }

    func makeNSView(context: Context) -> NSScrollView {
        let text = SignalTextView(usingTextLayoutManager: true)
        text.delegate = context.coordinator
        text.sentenceAt = { [analyzer] index in
            MainActor.assumeIsolated {
                analyzer.sentences.first { NSLocationInRange(index, $0.range) }
            }
        }
        text.isRichText = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 52, height: 44)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.paragraphSpacing = 10
        text.defaultParagraphStyle = paragraph
        text.font = .systemFont(ofSize: 17)
        text.typingAttributes[.paragraphStyle] = paragraph

        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.textView = text
        context.coordinator.observe()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        guard coordinator.noteID != noteID, let text = coordinator.textView else { return }
        coordinator.noteID = noteID
        text.string = initialText
        text.isEditable = noteID != nil
        analyzer.update(text: initialText)
        text.window?.makeFirstResponder(text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let analyzer: NoteAnalyzer
        weak var textView: SignalTextView?
        var noteID: URL?
        var onChange: (String) -> Void = { _ in }

        init(analyzer: NoteAnalyzer) { self.analyzer = analyzer }

        func textDidChange(_ notification: Notification) {
            guard let text = textView else { return }
            analyzer.update(text: text.string)
            onChange(text.string)
        }

        /// Re-draws highlights every time the analyzer's sentences change.
        func observe() {
            withObservationTracking {
                apply(analyzer.sentences)
            } onChange: { [weak self] in
                Task { @MainActor in self?.observe() }
            }
        }

        /// NSTextRange for a UTF-16 range of the document.
        private func textRange(_ range: NSRange, _ content: NSTextContentManager, _ whole: NSTextRange) -> NSTextRange? {
            guard let start = content.location(whole.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length) else { return nil }
            return NSTextRange(location: start, end: end)
        }

        private func apply(_ sentences: [AnalyzedSentence]) {
            guard let text = textView, let layout = text.textLayoutManager,
                  let content = layout.textContentManager else { return }
            let whole = layout.documentRange
            for key in [NSAttributedString.Key.backgroundColor, .underlineStyle, .underlineColor] {
                layout.removeRenderingAttribute(key, for: whole)
            }
            for sentence in sentences {
                guard let start = content.location(whole.location, offsetBy: sentence.range.location),
                      let end = content.location(start, offsetBy: sentence.range.length),
                      let range = NSTextRange(location: start, end: end) else { continue }
                guard let grammar = sentence.signals?.signals["grammar"] else {
                    // Still being analysed: a quiet dotted line, never the old colour.
                    layout.addRenderingAttribute(.underlineStyle,
                        value: NSUnderlineStyle([.single, .patternDot]).rawValue, for: range)
                    layout.addRenderingAttribute(.underlineColor, value: NSColor.tertiaryLabelColor, for: range)
                    continue
                }
                // Graphite: a soft band under each sentence, red and heavier for a likely mistake.
                let wrong = grammar.value == "yes"
                layout.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, for: range)
                layout.addRenderingAttribute(.underlineColor,
                    value: wrong ? NSColor.systemRed.withAlphaComponent(0.75) : NSColor.systemGreen.withAlphaComponent(0.3),
                    for: range)
                if wrong {
                    layout.addRenderingAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.06), for: range)
                }
            }
            // Mechanics: amber dots under a misspelled word, or under the sentence for other slips.
            let amber = NSColor.systemOrange
            let dotted = NSUnderlineStyle([.single, .patternDot]).rawValue
            for sentence in sentences {
                for issue in sentence.mechanics ?? [] {
                    let local = issue.range ?? NSRange(location: 0, length: sentence.range.length)
                    let absolute = NSRange(location: sentence.range.location + local.location, length: local.length)
                    guard let range = textRange(absolute, content, whole) else { continue }
                    if issue.kind == .spelling || sentence.signals?.signals["grammar"]?.value != "yes" {
                        layout.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | dotted, for: range)
                        layout.addRenderingAttribute(.underlineColor, value: amber, for: range)
                    }
                }
            }
            text.refreshHover()
        }
    }
}

/// Shows a card with every signal when the pointer rests on a sentence.
final class SignalTextView: NSTextView {
    var sentenceAt: (Int) -> AnalyzedSentence? = { _ in nil }
    private let popover = NSPopover()
    private var hovered: AnalyzedSentence?
    private var lastPoint: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo?["hover"] != nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: ["hover": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        lastPoint = convert(event.locationInWindow, from: nil)
        refreshHover()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        lastPoint = nil
        refreshHover()
    }

    override func keyDown(with event: NSEvent) {
        popover.performClose(nil)  // typing hides the card
        hovered = nil
        super.keyDown(with: event)
    }

    func refreshHover() {
        guard let point = lastPoint, (textStorage?.length ?? 0) > 0 else { return close() }
        let index = characterIndexForInsertion(at: point)
        guard let sentence = sentenceAt(index), let rect = rect(of: sentence.range), rect.contains(point) || rect.insetBy(dx: 0, dy: -4).contains(point) else {
            return close()
        }
        if sentence == hovered, popover.isShown { return }
        hovered = sentence
        let host = NSHostingController(rootView: SentenceCard(sentence: sentence))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .semitransient
        popover.animates = !popover.isShown
        popover.show(relativeTo: NSRect(x: point.x, y: rect.minY, width: 1, height: rect.height), of: self, preferredEdge: .maxY)
    }

    private func close() {
        hovered = nil
        if popover.isShown { popover.performClose(nil) }
    }

    /// Bounding box of a UTF-16 range, in this view's coordinates.
    private func rect(of range: NSRange) -> NSRect? {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let start = content.location(layout.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        var box: NSRect?
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            box = box.map { $0.union(frame) } ?? frame
            return true
        }
        let origin = textContainerOrigin
        return box?.offsetBy(dx: origin.x, dy: origin.y)
    }
}
