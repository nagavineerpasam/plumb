import SwiftUI
import WritingSignalsCore

/// Every signal for one sentence, shown when hovering it. Words only, one row per signal.
struct SentenceCard: View {
    let sentence: AnalyzedSentence
    /// A word the recognizer was unsure of, when the pointer is on one.
    var unsureWord: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let unsureWord {
                Label("Plumb wasn't sure it heard “\(unsureWord)”. Try saying it more clearly.", systemImage: "waveform")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if Palette.grammarReady, sentence.signals?.signals["grammar"]?.value == "yes" {
                Label(Explanations.grammar(for: sentence), systemImage: "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array((sentence.mechanics ?? []).enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if Palette.flowReady, sentence.flow?.value == "yes" {
                Label("Doesn't follow from the previous sentence", systemImage: "arrow.turn.down.right")
                    .font(.callout).foregroundStyle(.red)
            }
            if let signals = sentence.signals?.signals {
                if Palette.grammarReady, let score = sentence.correctness {
                    HStack {
                        Text("Score").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((score * 100).rounded()))")
                            .fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(Palette.band(score))
                    }
                    .font(.callout)
                }
                ForEach(Palette.order.filter { $0 != "grammar" }, id: \.self) { name in
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
        let mistake = (name == "grammar" || name == "sense") && signal.value == "yes"
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
        if name == "sense" {
            return signal.value == "yes" ? "Doesn't read as correct English" : "Makes sense"
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

/// What to tell the learner about a grammar mistake: where it is and what kind, never the answer.
@MainActor
enum Explanations {
    /// The card's line, e.g. Verb tense: check when this happened. Which form of “goes” fits?
    static func grammar(for sentence: AnalyzedSentence) -> String {
        GrammarHint.line(for: sentence.text, pointer: sentence.pointer)
    }

    /// The short version for the "Needs a look" list.
    static func short(for sentence: String, pointer: WordPointer?) -> String {
        GrammarHint.short(for: sentence, pointer: pointer)
    }

    /// Where to underline within the sentence: the word Plumb points at.
    static func wordRange(for sentence: AnalyzedSentence) -> NSRange? {
        sentence.pointer?.range
    }
}
