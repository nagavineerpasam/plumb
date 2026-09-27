import XCTest
@testable import WritingSignalsCore

final class FeedbackStoreTests: XCTestCase {
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }
    private let note = URL(fileURLWithPath: "/notes/Weekend plans.md")

    func testEveryNoteHasSmartFeedbackOnUntilTurnedOff() throws {
        let path = file()
        let store = FeedbackStore(file: path)
        XCTAssertTrue(store.isOn(note))

        try store.set(note, on: false)

        XCTAssertFalse(FeedbackStore(file: path).isOn(note), "remembered across launches")
        try store.set(note, on: true)
        XCTAssertTrue(FeedbackStore(file: path).isOn(note))
    }

    func testTheChoiceFollowsARenameAndGoesWithADelete() throws {
        let store = FeedbackStore(file: file())
        let renamed = URL(fileURLWithPath: "/notes/Hiking.md")
        try store.set(note, on: false)

        try store.renamed(note, to: renamed)
        XCTAssertFalse(store.isOn(renamed))
        XCTAssertTrue(store.isOn(note))

        try store.deleted(renamed)
        XCTAssertTrue(store.isOn(renamed))
    }
}
