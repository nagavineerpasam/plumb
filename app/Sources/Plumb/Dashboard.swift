import SwiftUI
import WritingSignalsCore

/// The whole note at a glance, updated live as the writer types. Every mistake is listed.
struct Dashboard: View {
    let summary: NoteSummary
    let pending: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if pending > 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Analysing \(pending) \(pending == 1 ? "sentence" : "sentences")…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                if summary.scoredSentences == 0 && summary.mechanics.isEmpty {
                    ContentUnavailableView("Start writing", systemImage: "text.cursor",
                        description: Text("Each sentence is checked as soon as you pause."))
                        .padding(.top, 40)
                } else {
                    section("Grammar") { grammar }
                    section("Spelling & punctuation") { mechanics }
                    if !summary.emotion.isEmpty { section("Emotion") { mix(summary.emotion, colors: Palette.emotions) } }
                    if !summary.tone.isEmpty { section("Tone") { mix(summary.tone, colors: Palette.tones) } }
                    if summary.confidence != nil { section("Voice") { voice } }
                }
            }
            .padding(14)
            .animation(.smooth, value: summary)
        }
    }

    // MARK: Sections

    private var grammar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Gauge(value: Double(correctCount), in: 0...Double(max(summary.scoredSentences, 1))) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(correctCount)/\(summary.scoredSentences)").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(summary.grammarFlagged.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(correctCount) of \(summary.scoredSentences) \(summary.scoredSentences == 1 ? "sentence looks" : "sentences look") correct")
                        .font(.callout.weight(.medium))
                    Text(summary.grammarFlagged.isEmpty ? "No likely grammar mistakes" : "Underlined in red in your note")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(summary.grammarFlagged.enumerated()), id: \.offset) { _, sentence in
                finding(color: .red, title: "Likely a grammar mistake", detail: sentence)
            }
        }
    }

    @ViewBuilder
    private var mechanics: some View {
        if summary.mechanics.isEmpty {
            Label("No mistakes found", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(summary.mechanics.enumerated()), id: \.offset) { _, found in
                    finding(color: .orange, title: found.issue.message, detail: found.sentence)
                }
            }
        }
    }

    private var voice: some View {
        VStack(spacing: 14) {
            ForEach(["confidence", "clarity", "formality"], id: \.self) { name in
                if let value = score(name), let (low, high) = Palette.scales[name] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Palette.titles[name] ?? name).font(.callout)
                            Spacer()
                            Text(Palette.word(for: name, at: value)).font(.callout).foregroundStyle(.secondary)
                        }
                        ScaleBar(value: value, low: low, high: high)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func finding(color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    /// Shares as one segmented bar, with sentence counts underneath.
    private func mix(_ shares: [String: Double], colors: [String: Color]) -> some View {
        let items = shares.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(items, id: \.key) { label, share in
                        Rectangle().fill(colors[label] ?? .gray)
                            .frame(width: max(0, (geo.size.width - CGFloat(items.count - 1) * 2) * share))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            FlowLegend(items: items.map { label, share in
                (label.capitalized, colors[label] ?? .gray, Int((share * Double(summary.scoredSentences)).rounded()))
            }, total: summary.scoredSentences)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
    }

    private var correctCount: Int {
        summary.scoredSentences - Int(((summary.grammarErrorRate ?? 0) * Double(summary.scoredSentences)).rounded())
    }

    private func score(_ name: String) -> Double? {
        switch name {
        case "confidence": summary.confidence
        case "clarity": summary.clarity
        default: summary.formality
        }
    }
}

/// Legend entries that wrap onto new lines instead of running off the panel.
private struct FlowLegend: View {
    let items: [(String, Color, Int)]
    let total: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { entries }
            VStack(alignment: .leading, spacing: 4) { entries }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var entries: some View {
        ForEach(items, id: \.0) { label, color, count in
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                Text("\(label) · \(count) of \(total)")
            }
        }
    }
}
