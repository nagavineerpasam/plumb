import Foundation

/// Which notes have Smart feedback turned off, kept in a small JSON file next to the notes'
/// progress. Every note is on unless turned off; the choice follows renames.
public final class FeedbackStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var off: Set<URL> = []

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file), let urls = try? JSONDecoder().decode([URL].self, from: data) {
            off = Set(urls)
        }
    }

    public func isOn(_ note: URL) -> Bool { lock.withLock { !off.contains(note) } }

    public func set(_ note: URL, on: Bool) throws {
        try change { if on { $0.remove(note) } else { $0.insert(note) } }
    }

    public func renamed(_ old: URL, to new: URL) throws {
        try change { if $0.remove(old) != nil { $0.insert(new) } }
    }

    public func deleted(_ note: URL) throws {
        try change { $0.remove(note) }
    }

    private func change(_ edit: (inout Set<URL>) -> Void) throws {
        let snapshot: [URL] = lock.withLock {
            edit(&off)
            return off.sorted { $0.path < $1.path }
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}
