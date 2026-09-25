import AppKit
import SwiftUI
import WritingSignalsCore

@main
struct WritingSignalsApp: App {
    @State private var model = AppModel()

    init() {
        // Launched from `swift run` there is no bundle, so ask to be a regular foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Writing Signals") {
            SignalEditor(analyzer: model.analyzer)
                .frame(minWidth: 640, minHeight: 420)
                .overlay(alignment: .bottomTrailing) {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).padding(8)
                }
        }
    }
}

@MainActor @Observable
final class AppModel {
    let analyzer: NoteAnalyzer
    private(set) var status = "Starting…"
    private let worker: WorkerClient

    init() {
        let (events, sink) = AsyncStream.makeStream(of: WorkerEvent.self)
        worker = WorkerClient(executable: WorkerLocation.python) { sink.yield($0) }
        analyzer = NoteAnalyzer(client: worker)
        Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        do { try worker.start() } catch { status = "Could not start the signal worker: \(error)" }
    }

    private func handle(_ event: WorkerEvent) {
        switch event {
        case .ready: status = "Ready"
        case let .progress(done, total): status = "Downloading models \(done * 100 / max(total, 1))%"
        case let .failed(message): status = message
        case .exited: status = "Signal worker stopped"
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
}
