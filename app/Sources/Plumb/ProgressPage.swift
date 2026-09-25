import Charts
import SwiftUI
import WritingSignalsCore

/// How the writer is improving: a smooth line through one dot per note (when it was last
/// edited, at its Correctness), with hover details, click-to-open and a 7-day summary.
struct ProgressPage: View {
    let progress: ProgressStore
    /// Changes whenever a score is recorded, so the chart refreshes.
    let version: Int
    let notes: [Note]
    let open: (Note) -> Void

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", all = "All"
        var id: String { rawValue }
        var start: Date {
            switch self {
            case .week: Date().addingTimeInterval(-7 * 86_400)
            case .month: Date().addingTimeInterval(-30 * 86_400)
            case .all: .distantPast
            }
        }
    }

    @State private var range = Range.month
    @State private var hovered: ProgressStore.Point?

    private var points: [ProgressStore.Point] { _ = version; return progress.points(since: range.start) }
    private func title(_ point: ProgressStore.Point) -> String {
        point.note.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if points.isEmpty {
                ContentUnavailableView("No progress yet", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Each note you write becomes a dot here. Older notes are scored quietly while you're away from the keyboard."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .padding(.horizontal, 52).padding(.top, 40).padding(.bottom, 32)
        .animation(.smooth, value: range)
    }

    private var header: some View {
        let week = { _ = version; return progress.weeklySummary() }()
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progress").font(.system(size: 24, weight: .semibold))
                if let average = week.average {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int((average * 100).rounded()))")
                            .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Palette.band(average))
                        Text("average score this week").foregroundStyle(.secondary)
                        if let change = week.change {
                            let points = Int((change * 100).rounded())
                            Label("\(points >= 0 ? "+" : "−")\(abs(points)) pts vs last week",
                                  systemImage: points >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(points >= 0 ? Color.green : Color.red)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background((points >= 0 ? Color.green : Color.red).opacity(0.12), in: Capsule())
                        }
                    }
                } else {
                    Text("Write this week to see your average.").foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 220)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points, id: \.note) { point in
                AreaMark(x: .value("Edited", point.date), y: .value("Score", point.correctness))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Edited", point.date), y: .value("Score", point.correctness))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Edited", point.date), y: .value("Score", point.correctness))
                    .symbolSize(hovered == point ? 140 : 60)
                    .foregroundStyle(Palette.band(point.correctness))
            }
            if let hovered {
                RuleMark(x: .value("Edited", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(hovered)).font(.callout.weight(.semibold))
                            Text(hovered.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Score \(Int((hovered.correctness * 100).rounded()))")
                                .font(.callout.weight(.medium)).foregroundStyle(Palette.band(hovered.correctness))
                        }
                        .padding(10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    }
            }
        }
        .chartYScale(domain: 0...1.05)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v * 100))") } }
            }
        }
        .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.clear); AxisValueLabel() } }
        .chartOverlay { chart in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case let .active(location) = phase, let frame = chart.plotFrame else {
                            hovered = nil
                            NSCursor.arrow.set()
                            return
                        }
                        let x = location.x - geo[frame].origin.x
                        hovered = points.min { a, b in
                            abs((chart.position(forX: a.date) ?? 0) - x) < abs((chart.position(forX: b.date) ?? 0) - x)
                        }
                        (hovered == nil ? NSCursor.arrow : NSCursor.pointingHand).set()  // a click opens the note
                    }
                    .onTapGesture {
                        if let hovered, let note = notes.first(where: { $0.url == hovered.note }) { open(note) }
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
