import SwiftUI
import WritingSignalsCore

/// "Soft" signals panel: a few rounded tiles with big, clear answers. Every issue is listed.
struct Dashboard: View {
    let summary: NoteSummary
    let pending: Int
    var checkFlow: () async -> Void = {}
    @State private var checkingFlow = false

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
                    if summary.confidence != nil {
                        tile("Voice") { voiceBars }
                    }
                }
            }
            .animation(.smooth, value: summary)
        }
        .scrollIndicators(.never)
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
        if Palette.grammarReady { summary.grammarFlagged.forEach { add($0, .red, "Grammar mistake") } }
        if Palette.senseReady { summary.senseFlagged.forEach { add($0, .red, "Doesn't make sense") } }
        if Palette.flowReady { summary.flowFlagged.forEach { add($0, .red, "Doesn't follow on") } }
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

    /// Tone and emotion as words, then the three scales as labelled bars.
    private var voiceBars: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tone = summary.tone.max(by: { $0.value < $1.value })?.key { textRow("Tone", tone.capitalized) }
            if let emotion = summary.emotion.max(by: { $0.value < $1.value })?.key { textRow("Emotion", emotion.capitalized) }
            ForEach(["confidence", "clarity", "formality"], id: \.self) { name in
                if let value = scale(name) {
                    VStack(alignment: .leading, spacing: 8) {
                        textRow(Palette.titles[name] ?? name, Palette.word(for: name, at: value))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule().fill(Color.accentColor.opacity(0.75)).frame(width: max(6, geo.size.width * value))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private func textRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            Text(value).font(.body).foregroundStyle(.secondary)
        }
    }

    private func scale(_ name: String) -> Double? {
        switch name {
        case "confidence": summary.confidence
        case "clarity": summary.clarity
        default: summary.formality
        }
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
