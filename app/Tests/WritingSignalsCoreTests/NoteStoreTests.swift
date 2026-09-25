import XCTest
import WritingSignalsCore

@MainActor
final class NoteStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNotesSurviveARelaunchAsPlainMarkdownFiles() throws {
        let store = try NoteStore(folder: folder)
        let note = try store.create()
        try store.save("# Plan\nWe ship on Friday.", to: note)

        let reopened = try NoteStore(folder: folder)

        XCTAssertEqual(reopened.notes.map(\.title), ["Untitled"])
        XCTAssertEqual(try reopened.text(of: reopened.notes[0]), "# Plan\nWe ship on Friday.")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Untitled.md"), encoding: .utf8),
                       "# Plan\nWe ship on Friday.")
    }

    func testNewNotesGetUniqueTitles() throws {
        let store = try NoteStore(folder: folder)

        _ = try store.create()
        _ = try store.create()

        XCTAssertEqual(Set(store.notes.map(\.title)), ["Untitled", "Untitled 2"])
    }

    func testRenameKeepsTheTextAndRenamesTheFile() throws {
        let store = try NoteStore(folder: folder)
        let note = try store.create()
        try store.save("Hello.", to: note)

        let renamed = try store.rename(note, to: "Letter/Draft")

        XCTAssertEqual(store.notes.map(\.title), ["Letter-Draft"])
        XCTAssertEqual(try store.text(of: renamed), "Hello.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled.md").path))
    }

    func testRenameToAnExistingTitleDoesNotOverwriteIt() throws {
        let store = try NoteStore(folder: folder)
        let first = try store.create()
        try store.save("First.", to: first)
        let second = try store.create()

        let renamed = try store.rename(second, to: "Untitled")

        XCTAssertEqual(renamed.title, "Untitled 2")
        XCTAssertEqual(try store.text(of: first), "First.")
    }

    func testDeleteRemovesTheNote() throws {
        let store = try NoteStore(folder: folder)
        let note = try store.create()

        try store.delete(note)

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
