import SwiftUI
import WritingSignalsCore

/// "Soft" signals panel: a few rounded tiles with big, clear answers. Every issue is listed.
struct Dashboard: View {
    let summary: NoteSummary
    let pending: Int
    /// Whether the note has any text; the welcome tile shows only for an empty note.
    var hasText = true
    /// Changes when a different note opens, so the previous note's values aren't shown.
    var noteID: URL?
    var checkFlow: () async -> Void = {}
    @State private var checkingFlow = false
    /// The last fully scored summary. While sentences are re-checked the tiles keep these values
    /// (with a small spinner) instead of emptying, then animate to the new ones.
    @State private var settled: NoteSummary?

    /// Scored values from the last settled summary, spelling and punctuation always live.
    private var shown: NoteSummary {
        guard var s = settled else { return summary }
        s.mechanics = summary.mechanics
        return s
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !hasText {
                    tile("Plumb") {
                        Text("Start writing. Each sentence is checked as soon as you pause.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    tile("Correctness", busy: pending > 0) { correctness }
                    tile("Needs a look") { issues }
                    if Palette.flowReady {
                        Button {
                            checkingFlow = true
                            Task { await checkFlow(); checkingFlow = false }
                        } label: {
                            Label(checkingFlow ? "Checking flow…" : "Check flow", systemImage: "arrow.triangle.branch")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(checkingFlow)
                        .help("Check whether each sentence follows on from the one before it")
                    }
                    tile("Voice", busy: pending > 0) { voiceBars }
                }
            }
            .animation(.smooth(duration: 0.35), value: shown)
        }
        .scrollIndicators(.never)
        .onChange(of: summary, initial: true) { _, new in
            if new.scoredSentences > 0 || pending == 0 { settled = new }
        }
        .onChange(of: pending) { _, now in if now == 0 { settled = summary } }
        .onChange(of: noteID) { _, _ in settled = nil }
    }

    @ViewBuilder
    private var correctness: some View {
        if !Palette.grammarReady {
            Label("The grammar check is training. Your score appears once it passes its accuracy test.",
                  systemImage: "hourglass")
                .font(.body).foregroundStyle(.secondary)
        } else {
            let score = shown.correctness
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(score.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: score ?? 0))
                    .foregroundStyle(score.map(band) ?? .secondary)
                Text(score.map(verdict) ?? "Checking…").font(.body).foregroundStyle(.secondary)
            }
            bar(score ?? 0, color: score.map(band) ?? .secondary)
        }
    }

    /// One short line per issue, in reading order. Hovering a sentence shows its details.
    @ViewBuilder
    private var issues: some View {
        let items = issueGroups.flatMap(\.items)
        if items.isEmpty {
            Label("Nothing to fix", systemImage: "checkmark.circle.fill")
                .font(.body).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in row(item.color, item.text) }
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
        if Palette.grammarReady { shown.grammarFlagged.forEach { add($0, .red, "Grammar mistake") } }
        if Palette.senseReady { shown.senseFlagged.forEach { add($0, .red, "Doesn't make sense") } }
        if Palette.flowReady { shown.flowFlagged.forEach { add($0, .red, "Doesn't follow on") } }
        shown.mechanics.forEach { add($0.sentence, .orange, $0.issue.message) }
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

    /// Tone and emotion as words, then the three scales as labelled bars.
    private var voiceBars: some View {
        VStack(alignment: .leading, spacing: 14) {
            textRow("Tone", shown.tone.max(by: { $0.value < $1.value })?.key.capitalized ?? "–")
            textRow("Emotion", shown.emotion.max(by: { $0.value < $1.value })?.key.capitalized ?? "–")
            ForEach(["confidence", "clarity", "formality"], id: \.self) { name in
                let value = scale(name)
                VStack(alignment: .leading, spacing: 8) {
                    textRow(Palette.titles[name] ?? name, value.map { Palette.word(for: name, at: $0) } ?? "–")
                    bar(value ?? 0, color: Color.accentColor.opacity(0.75))
                }
            }
        }
    }

    private func textRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            Text(value).font(.body).foregroundStyle(.secondary)
                .contentTransition(.interpolate)
        }
    }

    private func scale(_ name: String) -> Double? {
        switch name {
        case "confidence": shown.confidence
        case "clarity": shown.clarity
        default: shown.formality
        }
    }

    /// A 0...1 bar whose fill slides to new values instead of jumping.
    private func bar(_ value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: value > 0 ? max(6, geo.size.width * value) : 0)
            }
        }
        .frame(height: 6)
    }

    private func tile<Content: View>(_ title: String, busy: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if busy { ProgressView().controlSize(.mini).transition(.opacity) }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }


}
