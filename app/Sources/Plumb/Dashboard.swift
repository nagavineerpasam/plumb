import SwiftUI
import WritingSignalsCore

/// "Soft" signals panel: a few rounded tiles with big, clear answers. Every issue is listed.
struct Dashboard: View {
    let summary: NoteSummary
    let pending: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if pending > 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking \(pending) \(pending == 1 ? "sentence" : "sentences")…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6).padding(.top, 2)
                }
                if summary.scoredSentences == 0 && summary.mechanics.isEmpty {
                    tile("Plumb") {
                        Text("Start writing. Each sentence is checked as soon as you pause.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    if !Palette.grammarReady {
                        tile("Correct") {
                            Label("The grammar check is training. It switches on once it passes its accuracy test.",
                                  systemImage: "hourglass")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        tile("Correct") {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(correctCount)/\(summary.scoredSentences)")
                                    .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                                Text("sentences").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    tile("Needs a look") { issues }
                    if !voice.isEmpty {
                        tile("Voice") {
                            WrapLayout(spacing: 6) {
                                ForEach(voice, id: \.self) { word in
                                    Text(word).font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Palette.canvas, in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .animation(.smooth, value: summary)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var issues: some View {
        let grammar = Palette.grammarReady ? summary.grammarFlagged : []
        if grammar.isEmpty && summary.mechanics.isEmpty {
            Label("Nothing to fix", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(grammar.enumerated()), id: \.offset) { _, sentence in
                    row(.red, "Grammar: “\(sentence)”")
                }
                ForEach(Array(summary.mechanics.enumerated()), id: \.offset) { _, found in
                    row(.orange, found.issue.message, detail: found.sentence)
                }
            }
        }
    }

    private func row(_ color: Color, _ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).lineLimit(3)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
    }

    /// The note's voice in a few words: most common tone and emotion, and the three scales.
    private var voice: [String] {
        var words: [String] = []
        if let tone = summary.tone.max(by: { $0.value < $1.value })?.key { words.append(tone.capitalized) }
        if let emotion = summary.emotion.max(by: { $0.value < $1.value })?.key, emotion != "neutral" {
            words.append(emotion.capitalized)
        }
        if let v = summary.confidence { words.append(Palette.word(for: "confidence", at: v)) }
        if let v = summary.clarity { words.append(Palette.word(for: "clarity", at: v)) }
        if let v = summary.formality { words.append(Palette.word(for: "formality", at: v)) }
        return words
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private var correctCount: Int {
        summary.scoredSentences - Int(((summary.grammarErrorRate ?? 0) * Double(summary.scoredSentences)).rounded())
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.items + [index], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
