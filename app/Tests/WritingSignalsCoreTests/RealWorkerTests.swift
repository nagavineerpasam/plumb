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

        XCTAssertTrue(["english", "plumb"].contains(results["s1"]?.model ?? ""))
        XCTAssertEqual(Set(results["s1"]?.signals.keys ?? [:].keys),
                       ["grammar", "sense", "tone", "formality", "emotion", "confidence", "clarity"])
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

    func testRealWorkerPointsAtAWord() async throws {
        let client = WorkerClient(executable: try devPython())
        try client.start()
        defer { client.stop() }
        let text = "She go to school every day."

        let results = try await client.locate([SentenceRequest(id: "s1", text: text),
                                                SentenceRequest(id: "s2", text: String(repeating: "word ", count: 40) + ".")])

        let pointer = try XCTUnwrap(results["s1"] ?? nil)
        XCTAssertEqual((text as NSString).substring(with: pointer.range), pointer.text)
        XCTAssertTrue(pointer.probability > 0 && pointer.probability <= 1)
        if let type = pointer.type { XCTAssertNotNil(GrammarHint.names[type], "a known mistake type") }  // run 4+ models only
        XCTAssertEqual(results["s2"], .some(nil), "too long to point in")
    }

    func testRealWorkerChecksFlow() async throws {
        let client = WorkerClient(executable: try devPython())
        try client.start()
        defer { client.stop() }

        let results = try await client.flow([
            FlowRequest(id: "s2", previous: "The report is due on Friday.", sentence: "I will send a draft on Thursday."),
        ])

        XCTAssertEqual(Set(results["s2"]?.distribution.keys ?? [:].keys), ["yes", "no"])
    }
}
