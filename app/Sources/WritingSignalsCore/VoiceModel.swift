import Foundation

/// The Whisper voice model on disk: downloaded once, the first time the user speaks, from the
/// release's plumb-voice.zip. An interrupted download resumes; a bad one leaves nothing behind.
public struct VoiceModel: Sendable {
    public static let releaseURL = URL(string: "https://github.com/nagavineerpasam/plumb/releases/latest/download/plumb-voice.zip")!
    /// What a complete model folder must contain.
    static let required = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc",
                           "config.json", "tokenizer.json"]

    public let folder: URL
    /// Where the download collects until it's complete.
    public var partialDownload: URL { folder.deletingLastPathComponent().appendingPathComponent("plumb-voice.zip.part") }

    public init(folder: URL) {
        self.folder = folder
    }

    public var isInstalled: Bool {
        Self.required.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Downloads (resuming a partial download), unzips and validates the model. `progress`
    /// reports 0...1 of the download.
    public func install(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let files = FileManager.default
        try files.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await download(url, progress: progress)

        let staging = folder.appendingPathExtension("installing")
        try? files.removeItem(at: staging)
        do {
            try unzip(partialDownload, into: staging)
            guard Self.required.allSatisfy({ files.fileExists(atPath: staging.appendingPathComponent($0).path) }) else {
                throw VoiceModelError.incomplete
            }
        } catch {
            // A download that doesn't unzip into a model is bad; start fresh next time.
            try? files.removeItem(at: staging)
            try? files.removeItem(at: partialDownload)
            throw error
        }
        try? files.removeItem(at: folder)
        try files.moveItem(at: staging, to: folder)
        try? files.removeItem(at: partialDownload)
    }

    private func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let files = FileManager.default
        if !files.fileExists(atPath: partialDownload.path) { files.createFile(atPath: partialDownload.path, contents: nil) }
        let out = try FileHandle(forWritingTo: partialDownload)
        defer { try? out.close() }
        var done = Int64(try out.seekToEnd())

        let total: Int64
        let bytes: AsyncThrowingStream<Data, Error>
        if url.isFileURL {
            total = Int64((try files.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
            bytes = Self.chunks(ofFile: url, from: done)
        } else {
            var request = URLRequest(url: url)
            if done > 0 { request.setValue("bytes=\(done)-", forHTTPHeaderField: "Range") }
            let (stream, response) = try await URLSession.shared.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 || status == 206 else { throw VoiceModelError.http(status) }
            if status == 200, done > 0 {  // the server ignored the range: start over
                try out.truncate(atOffset: 0)
                done = 0
            }
            total = done + max(response.expectedContentLength, 0)
            bytes = Self.chunks(of: stream)
        }
        if total > 0 { progress(Double(done) / Double(total)) }
        for try await chunk in bytes {
            try out.write(contentsOf: chunk)
            done += Int64(chunk.count)
            if total > 0 { progress(min(1, Double(done) / Double(total))) }
        }
        progress(1)
    }

    /// The rest of a local file from `offset`, a megabyte at a time.
    private static func chunks(ofFile url: URL, from offset: Int64) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            do {
                let handle = try FileHandle(forReadingFrom: url)
                try handle.seek(toOffset: UInt64(offset))
                while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { continuation.yield(chunk) }
                try handle.close()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Network bytes gathered into megabyte chunks, so progress and writes aren't per byte.
    private static func chunks(of stream: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var chunk = Data(capacity: 1 << 20)
                    for try await byte in stream {
                        chunk.append(byte)
                        if chunk.count == 1 << 20 { continuation.yield(chunk); chunk.removeAll(keepingCapacity: true) }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func unzip(_ zip: URL, into destination: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, destination.path]
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw VoiceModelError.corrupt }
    }
}

public enum VoiceModelError: LocalizedError {
    case http(Int), corrupt, incomplete

    public var errorDescription: String? {
        switch self {
        case .http(let status): "The voice download failed (HTTP \(status)). Check your connection and click Speak to try again."
        case .corrupt, .incomplete: "The voice download was damaged. Click Speak to download it again."
        }
    }
}
