import XCTest
import WritingSignalsCore

final class ProgressStoreTests: XCTestCase {
    private var file: URL!
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: file) }

    private func note(_ name: String) -> URL { URL(fileURLWithPath: "/notes/\(name).md") }

    func testPointsAreOnePerNoteInTimeOrderAndSurviveRelaunch() throws {
        let store = ProgressStore(file: file)
        try store.record(note("b"), correctness: 0.5, at: now)
        try store.record(note("a"), correctness: 0.9, at: now.addingTimeInterval(-day))
        try store.record(note("b"), correctness: 0.7, at: now.addingTimeInterval(60))  // edited again: moves

        let reopened = ProgressStore(file: file)

        XCTAssertEqual(reopened.points(since: .distantPast).map(\.correctness), [0.9, 0.7])
        XCTAssertEqual(reopened.points(since: .distantPast).map(\.note), [note("a"), note("b")])
    }

    func testRenameKeepsTheScoreAndDeleteRemovesIt() throws {
        let store = ProgressStore(file: file)
        try store.record(note("draft"), correctness: 0.8, at: now)
        try store.record(note("gone"), correctness: 0.4, at: now)

        try store.renamed(note("draft"), to: note("final"))
        try store.deleted(note("gone"))

        XCTAssertEqual(store.points(since: .distantPast).map(\.note), [note("final")])
        XCTAssertTrue(store.hasScore(note("final")))
        XCTAssertFalse(store.hasScore(note("draft")))
    }

    func testRangeAndWeeklySummary() throws {
        let store = ProgressStore(file: file)
        try store.record(note("old"), correctness: 0.4, at: now.addingTimeInterval(-10 * day))
        try store.record(note("lastweek"), correctness: 0.6, at: now.addingTimeInterval(-8 * day))
        try store.record(note("mon"), correctness: 0.8, at: now.addingTimeInterval(-3 * day))
        try store.record(note("today"), correctness: 1.0, at: now)

        XCTAssertEqual(store.points(since: now.addingTimeInterval(-7 * day)).map(\.correctness), [0.8, 1.0])
        let week = store.weeklySummary(now: now)
        XCTAssertEqual(week.average ?? -1, 0.9, accuracy: 0.0001)       // last 7 days: 0.8, 1.0
        XCTAssertEqual(week.change ?? -1, 0.4, accuracy: 0.0001)        // vs days 7-14: 0.4, 0.6 → 0.5
    }
}
