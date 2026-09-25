import SwiftUI
import WritingSignalsCore

/// Every signal for one sentence, shown when hovering it. Words only, one row per signal.
struct SentenceCard: View {
    let sentence: AnalyzedSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array((sentence.mechanics ?? []).enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let signals = sentence.signals?.signals {
                ForEach(Palette.order, id: \.self) { name in
                    if let signal = signals[name] { row(name, signal) }
                }
            } else {
                Label("Analysing…", systemImage: "ellipsis").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 300)
    }

    private func row(_ name: String, _ signal: Signal) -> some View {
        let mistake = name == "grammar" && signal.value == "yes"
        return HStack {
            Text(Palette.titles[name] ?? name).foregroundStyle(.secondary)
            Spacer()
            if signal.score != nil {
                Text(headline(name, signal))
            } else {
                Text(headline(name, signal))
                    .fontWeight(.medium)
                    .foregroundStyle(mistake ? Color.red : Color.primary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background((mistake ? Color.red : Color.secondary).opacity(mistake ? 0.14 : 0.12), in: Capsule())
            }
        }
        .font(.callout)
    }

    /// Scales name their position, choices name the top label or say "unsure".
    private func headline(_ name: String, _ signal: Signal) -> String {
        if name == "grammar" {
            let p = signal.distribution["yes"] ?? 0
            let base = signal.value == "yes" ? "Likely a mistake" : "Looks correct"
            return (0.35...0.65).contains(p) ? "\(base) · unsure" : base
        }
        if let score = signal.score { return Palette.word(for: name, at: score) }
        let ranked = signal.distribution.sorted { $0.value > $1.value }
        if ranked.count > 1, ranked[0].value - ranked[1].value < 0.08 {
            return "Unsure: \(ranked[0].key.capitalized) or \(ranked[1].key.capitalized)"
        }
        return signal.value.capitalized
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
