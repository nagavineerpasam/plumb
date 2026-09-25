import XCTest
import WritingSignalsCore

/// End to end: the real Python signal worker from the repo's dev environment.
final class RealWorkerTests: XCTestCase {
    func testRealWorkerScoresASentence() async throws {
        let python = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: python.path), "no dev venv at \(python.path)")

        let client = WorkerClient(executable: python)
        try client.start()
        defer { client.stop() }

        let results = try await client.score([SentenceRequest(id: "s1", text: "We are very happy with the result.")])

        XCTAssertEqual(results["s1"]?.model, "english")
        XCTAssertEqual(Set(results["s1"]?.signals.keys ?? [:].keys),
                       ["grammar", "tone", "formality", "emotion", "confidence", "clarity"])
    }
}
