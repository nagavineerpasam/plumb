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
                            .font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    tile("Correctness") {
                        if Palette.grammarReady, let score = summary.correctness {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(score, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(band(score))
                                Text(verdict(score)).font(.body).foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(band(score)).frame(width: max(6, geo.size.width * score))
                                }
                            }
                            .frame(height: 6)
                        } else {
                            Label("The grammar check is training. Your score appears once it passes its accuracy test.",
                                  systemImage: "hourglass")
                                .font(.body).foregroundStyle(.secondary)
                        }
                    }
                    tile("Needs a look") { issues }
                    if !voice.isEmpty {
                        tile("Voice") {
                            WrapLayout(spacing: 8) {
                                ForEach(voice, id: \.self) { word in
                                    Text(word).font(.callout.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
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

    /// Issues grouped under the sentence they belong to, in reading order.
    @ViewBuilder
    private var issues: some View {
        let groups = issueGroups
        if groups.isEmpty {
            Label("Nothing to fix", systemImage: "checkmark.circle.fill")
                .font(.body).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.sentence).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            row(item.color, item.text)
                        }
                    }
                }
            }
        }
    }

    private var issueGroups: [(sentence: String, items: [(color: Color, text: String)])] {
        var groups: [(sentence: String, items: [(color: Color, text: String)])] = []
        func add(_ sentence: String, _ color: Color, _ text: String) {
            if let i = groups.firstIndex(where: { $0.sentence == sentence }) {
                groups[i].items.append((color, text))
            } else {
                groups.append((sentence, [(color, text)]))
            }
        }
        if Palette.grammarReady { summary.grammarFlagged.forEach { add($0, .red, "Likely a grammar mistake") } }
        summary.mechanics.forEach { add($0.sentence, .orange, $0.issue.message) }
        return groups
    }

    private func row(_ color: Color, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(title).font(.body).lineLimit(3)
        }
    }

    private func band(_ score: Double) -> Color { score >= 0.85 ? .green : score >= 0.6 ? .orange : .red }

    private func verdict(_ score: Double) -> String {
        score >= 0.85 ? "Well written" : score >= 0.6 ? "A few things to fix" : "Needs work"
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
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
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
