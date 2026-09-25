import AppKit
import SwiftUI
import WritingSignalsCore

/// TextKit 2 editor. Signals are drawn as rendering attributes, which never touch the text.
struct SignalEditor: NSViewRepresentable {
    let analyzer: NoteAnalyzer

    func makeCoordinator() -> Coordinator { Coordinator(analyzer: analyzer) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.delegate = context.coordinator
        text.font = .systemFont(ofSize: 17)
        text.textContainerInset = NSSize(width: 24, height: 24)
        text.isRichText = false
        text.allowsUndo = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView,
              let layout = text.textLayoutManager,
              let content = layout.textContentManager else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        for sentence in analyzer.sentences {
            guard let grammar = sentence.signals?.signals["grammar"],
                  let start = content.location(content.documentRange.location, offsetBy: sentence.range.location),
                  let end = content.location(start, offsetBy: sentence.range.length),
                  let range = NSTextRange(location: start, end: end) else { continue }
            let color: NSColor = grammar.value == "yes" ? .systemRed : .systemGreen
            layout.addRenderingAttribute(.backgroundColor, value: color.withAlphaComponent(0.18), for: range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let analyzer: NoteAnalyzer
        init(analyzer: NoteAnalyzer) { self.analyzer = analyzer }

        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated { analyzer.update(text: text.string) }
        }
    }
}
