import XCTest
import WritingSignalsCore

/// End to end: the real Python signal worker from the repo's dev environment.
final class RealWorkerTests: XCTestCase {
    private func devPython() throws -> URL {
        let python = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: python.path), "no dev venv at \(python.path)")
        return python
    }

    func testRealWorkerScoresASentence() async throws {
        let client = WorkerClient(executable: try devPython())
        try client.start()
        defer { client.stop() }

        let results = try await client.score([SentenceRequest(id: "s1", text: "We are very happy with the result.")])

        XCTAssertEqual(results["s1"]?.model, "english")
        XCTAssertEqual(Set(results["s1"]?.signals.keys ?? [:].keys),
                       ["grammar", "tone", "formality", "emotion", "confidence", "clarity"])
    }

    func testWorkerIsRestartedAfterItCrashes() async throws {
        let client = WorkerClient(executable: try devPython())
        try client.start()
        defer { client.stop() }
        _ = try await client.score([SentenceRequest(id: "a", text: "Warm up.")])

        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-9", "-P", "\(getpid())", "-f", "writing_signals.worker"]
        try kill.run()
        kill.waitUntilExit()

        var result: [String: SentenceSignals]?
        for _ in 0..<60 where result == nil {
            result = try? await client.score([SentenceRequest(id: "b", text: "Back again.")])
            if result == nil { try await Task.sleep(for: .seconds(1)) }
        }
        XCTAssertNotNil(result?["b"])
    }

    @MainActor
    func testFastTypingOfANoteEndsFullyScored() async throws {
        let client = WorkerClient(executable: try devPython())
        try client.start()
        defer { client.stop() }
        let analyzer = NoteAnalyzer(client: client, debounce: .milliseconds(300))
        let note = "They is happy. We are thrilled to announce our new office! The meeting is tomorrow at ten."

        var typed = ""
        for character in note {
            typed.append(character)
            analyzer.update(text: typed)
            try await Task.sleep(for: .milliseconds(Int.random(in: 5...400)))
        }
        await analyzer.idle()

        XCTAssertEqual(analyzer.sentences.count, 3)
        XCTAssertEqual(analyzer.sentences.filter { $0.signals == nil }.map(\.text), [])
    }
}
