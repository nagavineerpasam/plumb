import Foundation
import Observation

public struct Note: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public var title: String { url.deletingPathExtension().lastPathComponent }
}

/// Notes are plain Markdown files, one per note, in a folder the user owns.
@MainActor @Observable
public final class NoteStore {
    public private(set) var notes: [Note] = []
    private let folder: URL
    private let files = FileManager.default

    public init(folder: URL) throws {
        self.folder = folder
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try reload()
    }

    public func create() throws -> Note {
        let note = Note(url: freeURL(for: "Untitled"))
        try save("", to: note)
        return note
    }

    public func text(of note: Note) throws -> String {
        try String(contentsOf: note.url, encoding: .utf8)
    }

    public func save(_ text: String, to note: Note) throws {
        try text.write(to: note.url, atomically: true, encoding: .utf8)
        try reload()
    }

    /// Never overwrites another note: a taken title gets a number, like "Untitled 2".
    public func rename(_ note: Note, to title: String) throws -> Note {
        let clean = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return note }
        let renamed = Note(url: freeURL(for: clean, ownedBy: note))
        guard renamed != note else { return note }
        try files.moveItem(at: note.url, to: renamed.url)
        try reload()
        return renamed
    }

    /// Moves the note to the Trash, so a mistaken delete can be undone in Finder.
    public func delete(_ note: Note) throws {
        try files.trashItem(at: note.url, resultingItemURL: nil)
        try reload()
    }

    private func freeURL(for title: String, ownedBy owner: Note? = nil) -> URL {
        var candidate = title
        var n = 1
        func taken(_ name: String) -> Bool {
            let url = folder.appendingPathComponent(name + ".md")
            return url != owner?.url && files.fileExists(atPath: url.path)
        }
        while taken(candidate) {
            n += 1
            candidate = "\(title) \(n)"
        }
        return folder.appendingPathComponent(candidate + ".md")
    }

    private func reload() throws {
        let urls = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "md" }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        notes = urls.sorted { modified($0) > modified($1) }.map(Note.init)
    }
}
