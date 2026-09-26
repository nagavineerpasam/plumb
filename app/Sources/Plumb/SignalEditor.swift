import AppKit
import SwiftUI
import WritingSignalsCore

/// TextKit 2 editor. Signals are drawn as rendering attributes, which never touch the text.
struct SignalEditor: NSViewRepresentable {
    let analyzer: NoteAnalyzer
    let dictation: Dictation
    /// Changes whenever a different note is opened, so its text replaces the editor's.
    let noteID: URL?
    let initialText: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(analyzer: analyzer, dictation: dictation) }

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
        text.textContainerInset = NSSize(width: 47, height: 14)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        // Space between lines, not a taller line: with a line-height multiple AppKit's cursor
        // grows to the full line height and towers over the text.
        paragraph.lineSpacing = 12
        paragraph.paragraphSpacing = 10
        text.defaultParagraphStyle = paragraph
        text.font = .systemFont(ofSize: 17, weight: .medium)
        text.typingAttributes[.paragraphStyle] = paragraph

        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.textView = text
        dictation.textView = text
        context.coordinator.observe()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        guard coordinator.noteID != noteID, let text = coordinator.textView else { return }
        coordinator.noteID = noteID
        dictation.reset()
        text.string = initialText
        text.isEditable = noteID != nil
        analyzer.update(text: initialText)
        DispatchQueue.main.async { text.window?.makeFirstResponder(text) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let analyzer: NoteAnalyzer
        let dictation: Dictation
        weak var textView: SignalTextView?
        var noteID: URL?
        var onChange: (String) -> Void = { _ in }

        init(analyzer: NoteAnalyzer, dictation: Dictation) {
            self.analyzer = analyzer
            self.dictation = dictation
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            dictation.userEdited(range, replacementLength: (replacementString as NSString?)?.length ?? 0)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let text = textView else { return }
            analyzer.update(text: text.string)
            onChange(text.string)
        }

        /// Re-draws highlights every time the analyzer's sentences change.
        func observe() {
            withObservationTracking {
                apply(analyzer.sentences, grey: dictation.grey, hints: dictation.hints)
            } onChange: { [weak self] in
                Task { @MainActor in self?.observe() }
            }
        }

        /// Where a mechanics issue without its own range should be marked: the word it names,
        /// or the last word for a missing full stop.
        static func place(_ issue: MechanicsIssue, in sentence: String) -> NSRange {
            let text = sentence as NSString
            if issue.kind == .missingEndPunctuation {
                let last = text.range(of: #"\S+\s*$"#, options: .regularExpression)
                return last.location == NSNotFound ? NSRange(location: 0, length: text.length) : last
            }
            if issue.kind == .extraSpace {
                let gap = text.range(of: "  ")
                if gap.location != NSNotFound { return gap }
            }
            if let word = issue.word {
                let found = text.range(of: word, options: .caseInsensitive)
                if found.location != NSNotFound { return found }
            }
            return NSRange(location: 0, length: text.length)
        }

        /// NSTextRange for a UTF-16 range of the document.
        private func textRange(_ range: NSRange, _ content: NSTextContentManager, _ whole: NSTextRange) -> NSTextRange? {
            guard let start = content.location(whole.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length) else { return nil }
            return NSTextRange(location: start, end: end)
        }

        /// TextKit 2 rendering attributes draw background colours but ignore underlines, so the
        /// underlines are drawn by SignalTextView itself from `marks`.
        private func apply(_ sentences: [AnalyzedSentence], grey: NSRange?, hints: [NSRange]) {
            guard let text = textView, let layout = text.textLayoutManager,
                  let content = layout.textContentManager else { return }
            let whole = layout.documentRange
            layout.removeRenderingAttribute(.backgroundColor, for: whole)
            layout.removeRenderingAttribute(.foregroundColor, for: whole)
            if let grey, let range = textRange(grey, content, whole) {
                // Words still being recognised: light grey until they settle.
                layout.addRenderingAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, for: range)
            }
            var marks: [SignalTextView.Mark] = []
            for sentence in sentences {
                guard let signals = sentence.signals else { continue }  // still being checked: no mark
                let range = sentence.range
                let doesntRead = (Palette.flowReady && sentence.flow?.value == "yes")
                    || (Palette.senseReady && signals.signals["sense"]?.value == "yes")
                if doesntRead, let wash = textRange(range, content, whole) {
                    // Doesn't make sense, or doesn't follow on: a soft red wash over the sentence.
                    layout.addRenderingAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.14), for: wash)
                }
                if Palette.grammarReady, signals.signals["grammar"]?.value == "yes" {
                    if let word = Explanations.wordRange(for: sentence) {
                        // We know the word: underline just it, and wash the sentence faintly.
                        marks.append(.init(range: NSRange(location: range.location + word.location, length: word.length),
                                           color: .systemRed, dotted: false))
                        if !doesntRead, let wash = textRange(range, content, whole) {  // never weaken the stronger wash
                            layout.addRenderingAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.07), for: wash)
                        }
                    } else {
                        marks.append(.init(range: range, color: .systemRed, dotted: false))
                    }
                }
            }
            // Mechanics: amber dots under the word involved.
            for sentence in sentences {
                for issue in sentence.mechanics ?? [] {
                    let local = issue.range ?? Self.place(issue, in: sentence.text)
                    marks.append(.init(range: NSRange(location: sentence.range.location + local.location, length: local.length),
                                       color: .systemOrange, dotted: true))
                }
            }
            // "Say this more clearly": a faint grey dotted line under words the recognizer was unsure of.
            marks += hints.map { .init(range: $0, color: .tertiaryLabelColor, dotted: true) }
            text.marks = marks
            text.hints = hints
            text.refreshHover()
        }
    }
}

/// Shows a card with every signal when the pointer rests on a sentence.
final class SignalTextView: NSTextView {
    struct Mark: Equatable {
        let range: NSRange
        let color: NSColor
        let dotted: Bool
    }

    /// Underlines to draw: solid red for grammar mistakes, amber dots for spelling and punctuation.
    var marks: [Mark] = [] {
        didSet { if marks != oldValue { needsDisplay = true } }
    }
    var sentenceAt: (Int) -> AnalyzedSentence? = { _ in nil }
    /// Words the recognizer was unsure of; hovering one adds a "say it more clearly" line.
    var hints: [NSRange] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layout = textLayoutManager, let content = layout.textContentManager else { return }
        let origin = textContainerOrigin
        for mark in marks {
            guard let start = content.location(layout.documentRange.location, offsetBy: mark.range.location),
                  let end = content.location(start, offsetBy: mark.range.length),
                  let range = NSTextRange(location: start, end: end) else { continue }
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, baseline, _ in
                let y = origin.y + frame.minY + baseline + 4
                let line = NSBezierPath()
                line.move(to: NSPoint(x: origin.x + frame.minX, y: y))
                line.line(to: NSPoint(x: origin.x + frame.maxX, y: y))
                line.lineWidth = mark.dotted ? 2 : 2.5
                line.lineCapStyle = .round
                if mark.dotted { line.setLineDash([0.1, 4], count: 2, phase: 0) }
                mark.color.withAlphaComponent(mark.dotted ? 1 : 0.85).setStroke()
                line.stroke()
                return true
            }
        }
    }
    private let popover = NSPopover()
    private var hovered: AnalyzedSentence?
    private var lastPoint: NSPoint?
    private var closeTimer: Timer?

    /// Take the cursor as soon as the editor is on screen, so typing works without a click.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isEditable { DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        } }
    }

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
        closeNow()  // typing hides the card
        super.keyDown(with: event)
    }

    func refreshHover() {
        guard let point = lastPoint, (textStorage?.length ?? 0) > 0 else { return closeSoon() }
        let index = characterIndexForInsertion(at: point)
        guard let sentence = sentenceAt(index), let rect = rect(of: sentence.range), rect.contains(point) || rect.insetBy(dx: 0, dy: -4).contains(point) else {
            return closeSoon()
        }
        closeTimer?.invalidate()
        closeTimer = nil
        if sentence == hovered, popover.isShown { return }
        hovered = sentence
        let unsure = hints.first { NSLocationInRange(index, $0) }.map { (string as NSString).substring(with: $0) }
        let host = NSHostingController(rootView: SentenceCard(sentence: sentence, unsureWord: unsure))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .semitransient
        popover.animates = !popover.isShown
        popover.show(relativeTo: NSRect(x: point.x, y: rect.minY, width: 1, height: rect.height), of: self, preferredEdge: .maxY)
        paintCardBackground()
    }

    /// The popover's standard material is a dull grey in light mode; paint it (arrow included)
    /// the same white as the note page instead.
    private func paintCardBackground() {
        guard let frame = popover.contentViewController?.view.window?.contentView?.superview,
              !frame.subviews.contains(where: { $0.identifier == Self.cardBackground }) else { return }
        let background = CardBackgroundView(frame: frame.bounds)
        background.identifier = Self.cardBackground
        background.autoresizingMask = [.width, .height]
        frame.addSubview(background, positioned: .below, relativeTo: nil)
        frame.window?.hasShadow = true  // white on the white page: the shadow sets the card apart
        frame.window?.invalidateShadow()
    }
    private static let cardBackground = NSUserInterfaceItemIdentifier("cardBackground")

    /// Leaving a sentence doesn't close the card at once, so the pointer can travel onto it.
    /// It stays open while the pointer is over the card and closes shortly after it leaves both.
    private func closeSoon() {
        guard popover.isShown, closeTimer == nil else { return }
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let card = self.popover.contentViewController?.view.window,
                   card.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) { return }
                self.closeNow()
            }
        }
    }

    private func closeNow() {
        closeTimer?.invalidate()
        closeTimer = nil
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

/// Fills the hover card with the page colour, following light and dark mode.
private final class CardBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(Palette.card).setFill()
        dirtyRect.fill()
    }
}
