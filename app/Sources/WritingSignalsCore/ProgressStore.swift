import Foundation

/// Each note's latest Correctness and when it was last edited, kept in a small JSON file
/// outside the notes, so progress can be charted across notes over time.
public final class ProgressStore: @unchecked Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public let note: URL
        public let correctness: Double
        public let date: Date
    }

    public struct Summary: Equatable, Sendable {
        /// Average Correctness of notes edited in the last 7 days.
        public let average: Double?
        /// That average minus the average of the 7 days before.
        public let change: Double?
    }

    private let file: URL
    private let lock = NSLock()
    private var byNote: [URL: Point] = [:]

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let points = try? JSONDecoder().decode([Point].self, from: data) {
            byNote = Dictionary(points.map { ($0.note, $0) }, uniquingKeysWith: { $1 })
        }
    }

    /// The note's latest score; replaces any earlier one, so each note is one point.
    public func record(_ note: URL, correctness: Double, at date: Date) throws {
        try change { $0[note] = Point(note: note, correctness: correctness, date: date) }
    }

    public func renamed(_ old: URL, to new: URL) throws {
        try change { points in
            guard let point = points.removeValue(forKey: old) else { return }
            points[new] = Point(note: new, correctness: point.correctness, date: point.date)
        }
    }

    public func deleted(_ note: URL) throws {
        try change { $0.removeValue(forKey: note) }
    }

    public func hasScore(_ note: URL) -> Bool {
        lock.withLock { byNote[note] != nil }
    }

    /// Points edited on or after `start`, oldest first.
    public func points(since start: Date) -> [Point] {
        lock.withLock { byNote.values.filter { $0.date >= start }.sorted { $0.date < $1.date } }
    }

    public func weeklySummary(now: Date = Date()) -> Summary {
        let week: TimeInterval = 7 * 86_400
        let all = points(since: now.addingTimeInterval(-2 * week))
        func mean(_ points: [Point]) -> Double? {
            points.isEmpty ? nil : points.map(\.correctness).reduce(0, +) / Double(points.count)
        }
        let recent = mean(all.filter { $0.date > now.addingTimeInterval(-week) })
        let before = mean(all.filter { $0.date <= now.addingTimeInterval(-week) })
        return Summary(average: recent, change: recent.flatMap { r in before.map { r - $0 } })
    }

    private func change(_ edit: (inout [URL: Point]) -> Void) throws {
        let data: Data = try lock.withLock {
            edit(&byNote)
            return try JSONEncoder().encode(Array(byNote.values))
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
