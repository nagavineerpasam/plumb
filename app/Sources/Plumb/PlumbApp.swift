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
        // A packaged .app gets its icon from Info.plist; `swift run` needs it set here.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
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

    func apply() {
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
        do {
            store = try NoteStore(folder: WorkerLocation.notesFolder)
        } catch {
            store = nil
            self.error = "Could not open your notes folder: \(error.localizedDescription)"
        }
        Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        do { try worker.start() } catch { phase = .down("Could not start the signal worker: \(error.localizedDescription)") }
        open(store?.notes.first)
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
    }

    func open(_ note: Note?) {
        guard note != selection else { return }
        flush()
        selection = note
        openedText = (try? note.map { try store?.text(of: $0) ?? "" }) ?? ""
    }

    func edited(_ text: String) {
        guard let note = selection else { return }
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
    /// `WRITING_SIGNALS_PYTHON` wins; otherwise the repo's dev venv.
    static var python: URL {
        if let path = ProcessInfo.processInfo.environment["WRITING_SIGNALS_PYTHON"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
    }

    static var notesFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Plumb", isDirectory: true)
        // Notes written before the app was named Plumb move over once.
        let old = documents.appendingPathComponent("Writing Signals", isDirectory: true)
        let files = FileManager.default
        if !files.fileExists(atPath: folder.path), files.fileExists(atPath: old.path) {
            try? files.moveItem(at: old, to: folder)
        }
        return folder
    }
}
