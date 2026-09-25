import Charts
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
                    tile("Emotion mix") { donut(summary.emotion, colors: Palette.emotions) }
                    tile("Tone") { bars(summary.tone, colors: Palette.tones) }
                    tile("Voice") {
                        VStack(spacing: 14) {
                            ForEach(["confidence", "clarity", "formality"], id: \.self) { name in
                                if let value = score(name), let (low, high) = Palette.scales[name] {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(Palette.titles[name] ?? name).font(.subheadline.weight(.medium))
                                            Spacer()
                                            Text(value, format: .percent.precision(.fractionLength(0)))
                                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                        }
                                        ScaleBar(value: value, low: low, high: high)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
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
                Text("\(summary.scoredSentences) sentences").font(.caption).foregroundStyle(.secondary)
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
                    Text(correct, format: .percent.precision(.fractionLength(0))).font(.headline)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Gradient(colors: [.red, .orange, .green]))
                .scaleEffect(1.3)
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("sentences look correct").font(.subheadline)
                    let wrong = Int(((summary.grammarErrorRate ?? 0) * Double(summary.scoredSentences)).rounded())
                    Text(wrong == 0 ? "No likely mistakes" : "\(wrong) likely \(wrong == 1 ? "mistake" : "mistakes") highlighted in red")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func score(_ name: String) -> Double? {
        switch name {
        case "confidence": summary.confidence
        case "clarity": summary.clarity
        default: summary.formality
        }
    }

    private func donut(_ shares: [String: Double], colors: [String: Color]) -> some View {
        let items = shares.sorted { $0.value > $1.value }
        return HStack(spacing: 16) {
            Chart(items, id: \.key) { label, share in
                SectorMark(angle: .value("Share", share), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(colors[label] ?? .gray)
            }
            .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.key) { label, share in
                    HStack(spacing: 6) {
                        Circle().fill(colors[label] ?? .gray).frame(width: 8, height: 8)
                        Text(label.capitalized).font(.caption)
                        Spacer()
                        Text(share, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func bars(_ shares: [String: Double], colors: [String: Color]) -> some View {
        Chart(shares.sorted { $0.value > $1.value }, id: \.key) { label, share in
            BarMark(x: .value("Share", share), y: .value("Tone", label.capitalized))
                .foregroundStyle((colors[label] ?? .gray).gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...1.15)
        .chartXAxis(.hidden)
        .frame(height: CGFloat(max(shares.count, 1)) * 30)
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
