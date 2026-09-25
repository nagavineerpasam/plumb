import SwiftUI
import WritingSignalsCore

/// Every signal for one sentence, with its probabilities. Shown when hovering a sentence.
struct SentenceCard: View {
    let sentence: AnalyzedSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sentence.text)
                .font(.system(.callout, design: .serif))
                .lineLimit(3)
                .foregroundStyle(.secondary)
            if let signals = sentence.signals?.signals {
                ForEach(Palette.order, id: \.self) { name in
                    if let signal = signals[name] { row(name, signal) }
                }
            } else {
                Label("Analysing…", systemImage: "ellipsis").foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    @ViewBuilder
    private func row(_ name: String, _ signal: Signal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Palette.titles[name] ?? name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(headline(name, signal))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(name == "grammar" && signal.value == "yes" ? Color.red : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((name == "grammar" && signal.value == "yes" ? Color.red : Color.secondary).opacity(0.14), in: Capsule())
            }
            if let (low, high) = Palette.scales[name], let score = signal.score {
                ScaleBar(value: score, low: low, high: high)
            } else if name != "grammar" {
                ForEach(signal.distribution.sorted { $0.value > $1.value }.prefix(3), id: \.key) { label, p in
                    HStack(spacing: 8) {
                        Text(label.capitalized).font(.caption2).frame(width: 64, alignment: .leading)
                        ProgressView(value: p).tint(Palette.color(signal: name, value: label))
                        Text(p, format: .percent.precision(.fractionLength(0))).font(.caption2.monospacedDigit())
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func headline(_ name: String, _ signal: Signal) -> String {
        if name == "grammar" {
            let p = signal.distribution["yes"] ?? 0
            return signal.value == "yes"
                ? "Likely a mistake · \(Int((p * 100).rounded()))%"
                : "Looks correct · \(Int(((1 - p) * 100).rounded()))%"
        }
        let p = signal.distribution[signal.value] ?? 0
        return "\(signal.value.capitalized) · \(Int((p * 100).rounded()))%"
    }
}

/// A 0...1 position between two named ends.
struct ScaleBar: View {
    let value: Double
    let low: String
    let high: String

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor.gradient).frame(width: max(8, geo.size.width * value))
                }
            }
            .frame(height: 6)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
