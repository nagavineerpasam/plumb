import XCTest
import WritingSignalsCore

final class VoiceModelTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A zip laid out like plumb-voice.zip, with small stand-in files.
    private func makeModelZip() throws -> URL {
        let source = dir.appendingPathComponent("source")
        for part in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"] {
            let folder = source.appendingPathComponent(part)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 200_000).write(to: folder.appendingPathComponent("weight.bin"))
        }
        for file in ["config.json", "tokenizer.json"] {
            try Data("{}".utf8).write(to: source.appendingPathComponent(file))
        }
        let zip = dir.appendingPathComponent("plumb-voice.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", source.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        return zip
    }

    func testInstallsFromTheReleaseZipAndReportsProgress() async throws {
        let zip = try makeModelZip()
        let model = VoiceModel(folder: dir.appendingPathComponent("Voice"))
        XCTAssertFalse(model.isInstalled)
        let progress = Progress()

        try await model.install(from: zip) { progress.record($0) }

        XCTAssertTrue(model.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.folder.appendingPathComponent("TextDecoder.mlmodelc").path))
        XCTAssertEqual(progress.values.last, 1)
    }

    func testAnInterruptedDownloadResumesWhereItStopped() async throws {
        let zip = try makeModelZip()
        let model = VoiceModel(folder: dir.appendingPathComponent("Voice"))
        let whole = try Data(contentsOf: zip)
        try whole.prefix(whole.count / 2).write(to: model.partialDownload)
        let progress = Progress()

        try await model.install(from: zip) { progress.record($0) }

        XCTAssertTrue(model.isInstalled)
        XCTAssertGreaterThanOrEqual(progress.values.first ?? 0, 0.49, "starts from the half already downloaded")
    }

    func testACorruptDownloadLeavesNothingInstalled() async throws {
        let bad = dir.appendingPathComponent("plumb-voice.zip")
        try Data(repeating: 1, count: 50_000).write(to: bad)
        let model = VoiceModel(folder: dir.appendingPathComponent("Voice"))

        do {
            try await model.install(from: bad) { _ in }
            XCTFail("a corrupt zip must not install")
        } catch {}

        XCTAssertFalse(model.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.partialDownload.path), "a bad download isn't resumed")
    }
}

/// Collects progress reports from the installer's callback.
private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    var values: [Double] { lock.withLock { recorded } }
    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
}
