import SwiftUI
import WritingSignalsCore

/// The whole note at a glance, updated live as the writer types.
struct Dashboard: View {
    let summary: NoteSummary
    let pending: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if summary.scoredSentences == 0 {
                    ContentUnavailableView("Start writing",
                        systemImage: "text.cursor",
                        description: Text("Signals appear for each sentence as soon as you pause."))
                        .padding(.top, 40)
                } else {
                    grammar
                    tile("Mechanics") { mechanics }
                    tile("Emotion mix") { mix(summary.emotion, colors: Palette.emotions) }
                    tile("Tone") { mix(summary.tone, colors: Palette.tones) }
                    tile("Voice") {
                        VStack(spacing: 14) {
                            ForEach(["confidence", "clarity", "formality"], id: \.self) { name in
                                if let value = score(name), let (low, high) = Palette.scales[name] {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(Palette.titles[name] ?? name).font(.subheadline.weight(.medium))
                                            Spacer()
                                            Text(Palette.word(for: name, at: value))
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        ScaleBar(value: value, low: low, high: high)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .animation(.smooth, value: summary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Signals").font(.title2.weight(.semibold))
            Spacer()
            if pending > 0 {
                ProgressView().controlSize(.small)
                Text("\(pending) analysing").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(summary.scoredSentences == 1 ? "1 sentence" : "\(summary.scoredSentences) sentences")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var grammar: some View {
        let correct = 1 - (summary.grammarErrorRate ?? 0)
        return tile("Grammar") {
            HStack(spacing: 18) {
                Gauge(value: correct) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(correctCount)/\(summary.scoredSentences)").font(.headline).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.green)
                .scaleEffect(1.25)
                .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(correctCount) of \(summary.scoredSentences) \(summary.scoredSentences == 1 ? "sentence looks" : "sentences look") correct").font(.subheadline)
                    let wrong = Int(((summary.grammarErrorRate ?? 0) * Double(summary.scoredSentences)).rounded())
                    Text(wrong == 0 ? "No likely mistakes" : "\(wrong) likely \(wrong == 1 ? "mistake" : "mistakes") underlined in red")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var correctCount: Int {
        summary.scoredSentences - Int(((summary.grammarErrorRate ?? 0) * Double(summary.scoredSentences)).rounded())
    }

    private var mechanics: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.mechanicsIssues == 0 ? "checkmark.circle" : "exclamationmark.circle")
                .font(.title3).foregroundStyle(summary.mechanicsIssues == 0 ? Color.green : Color.orange)
            Text(summary.mechanicsIssues == 0 ? "Spelling, capitals and punctuation look fine"
                 : "\(summary.mechanicsIssues) spelling or punctuation \(summary.mechanicsIssues == 1 ? "slip" : "slips") underlined in amber")
                .font(.subheadline)
        }
    }

    private func score(_ name: String) -> Double? {
        switch name {
        case "confidence": summary.confidence
        case "clarity": summary.clarity
        default: summary.formality
        }
    }

    /// Shares as one segmented bar with a legend underneath.
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
            HStack(spacing: 12) {
                ForEach(items, id: \.key) { label, share in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(colors[label] ?? .gray).frame(width: 8, height: 8)
                        let count = Int((share * Double(summary.scoredSentences)).rounded())
                        Text("\(label.capitalized) · \(count) of \(summary.scoredSentences)")
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}
