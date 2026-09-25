import AppKit
import SwiftUI
import WritingSignalsCore

@main
struct PlumbApp: App {
    @State private var model = AppModel()

    init() {
        // Launched from `swift run` there is no bundle, so ask to be a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        // A packaged .app gets its icon from Info.plist; `swift run` has no bundle, so set it here.
        // (Bundle.module is only touched outside an .app, where it exists.)
        if !Bundle.main.bundlePath.hasSuffix(".app"),
           let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            NSApplication.shared.applicationIconImage = NSImage(contentsOf: url)
        }
        (UserDefaults.standard.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .system).apply()
    }

    var body: some Scene {
        WindowGroup("Plumb") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }

    @MainActor func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.headline)
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Divider().padding(.vertical, 4)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([WorkerLocation.notesFolder])
            } label: {
                Label("Show notes in Finder", systemImage: "folder")
            }
            .buttonStyle(.link)
        }
        .padding(20)
        .frame(width: 300)
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
    }
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case downloading(Int64, Int64, problem: String?)
        case ready
        case down(String)
    }

    let analyzer: NoteAnalyzer
    let dictation = Dictation()
    /// Each note's latest Correctness over time, for the Progress page.
    let progress = ProgressStore(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plumb/progress.json"))
    /// Bumped whenever a score is recorded, so the Progress page redraws.
    private(set) var progressVersion = 0
    var showingProgress = false
    private var lastEdit = Date()
    private var unscorable: Set<URL> = []
    private var backfill: Task<Void, Never>?
    let store: NoteStore?
    private(set) var phase = Phase.starting
    private(set) var selection: Note?
    private(set) var openedText = ""
    var showDashboard = true
    var error: String?

    private let worker: WorkerClient
    private var unsaved: (Note, String)?
    private var saveTask: Task<Void, Never>?

    init() {
        let (events, sink) = AsyncStream.makeStream(of: WorkerEvent.self)
        worker = WorkerClient(executable: WorkerLocation.python) { sink.yield($0) }
        analyzer = NoteAnalyzer(client: worker)
        let notesFolder = WorkerLocation.notesFolder
        var moved: [(from: URL, to: URL)] = []
        if let old = WorkerLocation.legacyNotes(), !FileManager.default.fileExists(atPath: notesFolder.path) {
            try? FileManager.default.createDirectory(at: notesFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? FileManager.default.moveItem(at: old, to: notesFolder)) != nil {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: notesFolder.path)) ?? []
                moved = files.map { (old.appendingPathComponent($0), notesFolder.appendingPathComponent($0)) }
            }
        }
        for (from, to) in moved { try? progress.renamed(from, to: to) }
        do {
            store = try NoteStore(folder: notesFolder)
        } catch {
            store = nil
            self.error = "Could not open your notes folder: \(error.localizedDescription)"
        }
        Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        startBackfill()
        do { try worker.start() } catch { phase = .down("Could not start the signal worker: \(error.localizedDescription)") }
        // First launch: open a note straight away, so the user can just start typing.
        if store?.notes.isEmpty == true { newNote() } else { open(store?.notes.first) }
    }

    var statusLine: String {
        switch phase {
        case .starting: "Loading language models…"
        case .downloading: "Downloading language models…"
        case .ready: "Signals on · runs on this Mac"
        case let .down(message): message
        }
    }

    private var statuses: [URL: NoteStatus] = [:]

    func status(of note: Note) -> NoteStatus { statuses[note.url] ?? .unchecked }

    /// Remembers the open note's state for its sidebar dot.
    func record(_ summary: NoteSummary) {
        guard let url = selection?.url else { return }
        let grammar = Palette.grammarReady && !summary.grammarFlagged.isEmpty
        statuses[url] = grammar ? .attention
            : summary.mechanicsIssues > 0 ? .mechanics
            : summary.scoredSentences > 0 ? .clean : .unchecked
        // Once every sentence is checked, the note's score becomes its point on the Progress chart.
        if analyzer.sentences.allSatisfy({ $0.signals != nil }), let score = summary.correctness {
            let edited = store?.notes.first { $0.url == url }?.modified ?? Date()
            try? progress.record(url, correctness: score, at: edited)
            progressVersion += 1
        }
    }

    /// Scores notes that have no Progress point yet, one at a time, only after 30 s without typing.
    func startBackfill() {
        backfill?.cancel()
        backfill = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, Date().timeIntervalSince(self.lastEdit) > 30,
                      !self.dictation.isListening,
                      let note = self.store?.notes.first(where: {
                          $0 != self.selection && !self.progress.hasScore($0.url) && !self.unscorable.contains($0.url)
                      }),
                      let text = try? self.store?.text(of: note) else { continue }
                let scorer = NoteAnalyzer(client: self.worker, debounce: .zero, retryDelay: .seconds(5))
                scorer.update(text: text)
                await scorer.idle()
                if let score = scorer.summary.correctness {
                    try? self.progress.record(note.url, correctness: score, at: note.modified)
                    self.progressVersion += 1
                } else {
                    self.unscorable.insert(note.url)  // empty note: nothing to score
                }
            }
        }
    }

    func open(_ note: Note?) {
        showingProgress = false
        guard note != selection else { return }
        flush()
        selection = note
        openedText = (try? note.map { try store?.text(of: $0) ?? "" }) ?? ""
    }

    func edited(_ text: String) {
        guard let note = selection else { return }
        lastEdit = Date()
        unsaved = (note, text)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    func newNote() {
        perform { if let note = try store?.create() { open(note) } }
    }

    func rename(_ note: Note, to title: String) {
        flush()
        perform {
            guard let renamed = try store?.rename(note, to: title) else { return }
            try? progress.renamed(note.url, to: renamed.url)
            if selection == note {
                // The editor reloads when the file changes; give it the text just saved, not the
                // text from when the note was opened.
                openedText = try store?.text(of: renamed) ?? openedText
                selection = renamed
            }
        }
    }

    func renameSelection(to title: String) {
        if let note = selection { rename(note, to: title) }
    }

    func delete(_ note: Note) {
        if selection == note { flush(); selection = nil; openedText = "" }
        perform { try store?.delete(note) }
        try? progress.deleted(note.url)
        progressVersion += 1
    }

    private func flush() {
        guard let (note, text) = unsaved else { return }
        unsaved = nil
        perform { try store?.save(text, to: note) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }

    private func handle(_ event: WorkerEvent) {
        withAnimation(.smooth) {
            switch event {
            case .ready:
                phase = .ready
            case let .progress(done, total):
                if done < total { phase = .downloading(done, total, problem: nil) }
            case let .failed(message):
                if case let .downloading(done, total, _) = phase {
                    phase = .downloading(done, total, problem: message)
                } else {
                    phase = .down(message)
                }
            case .exited:
                if case .downloading = phase { return }
                phase = .down("Signal worker restarting…")
            }
        }
    }
}

enum WorkerLocation {
    /// The Python shipped inside Plumb.app; else `WRITING_SIGNALS_PYTHON`; else the repo's dev venv.
    static var python: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        if let path = ProcessInfo.processInfo.environment["WRITING_SIGNALS_PYTHON"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
    }

    /// Plumb's own folder, which needs no permission prompt (unlike ~/Documents).
    static var notesFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plumb/Notes", isDirectory: true)
    }

    /// Notes from before Plumb kept them in its own folder, and where they are now. Only the dev
    /// build looks: in the packaged app, merely checking ~/Documents would trigger a permission prompt.
    static func legacyNotes() -> URL? {
        guard !Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ["Plumb", "Writing Signals"].map { documents.appendingPathComponent($0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
