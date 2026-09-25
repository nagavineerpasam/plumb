import Foundation

public enum WorkerEvent: Sendable, Equatable {
    case ready(catalogueVersion: String)
    case progress(downloaded: Int64, total: Int64)
    case failed(String)
    case exited
}

public enum WorkerError: Error, Equatable {
    case notRunning
    case exited
    case failed(String)
}

/// Runs the Python signal worker as a child process and speaks its JSON-lines protocol
/// over stdin/stdout. No network port is opened. If the worker dies unexpectedly it is
/// restarted, backing off from 1 s up to 30 s while it keeps failing.
public final class WorkerClient: SignalClient, @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let onEvent: @Sendable (WorkerEvent) -> Void

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var waiting: [String: CheckedContinuation<Incoming, Error>] = [:]
    private var nextID = 0
    private var stopping = false
    private var restartDelay: Duration = .seconds(1)

    public init(executable: URL,
                arguments: [String] = ["-m", "writing_signals.worker"],
                environment: [String: String]? = nil,
                onEvent: @escaping @Sendable (WorkerEvent) -> Void = { _ in }) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.onEvent = onEvent
    }

    public func start() throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.standardError
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.receive(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in self?.terminated() }
        try process.run()
        lock.withLock {
            self.stopping = false
            self.process = process
            self.input = stdin.fileHandleForWriting
        }
    }

    public func stop() {
        let (process, input) = lock.withLock {
            stopping = true
            return (self.process, self.input)
        }
        try? input?.write(contentsOf: Data("{\"type\":\"shutdown\"}\n".utf8))
        process?.waitUntilExit()
    }

    public var isRunning: Bool { lock.withLock { process?.isRunning ?? false } }

    public func score(_ sentences: [SentenceRequest]) async throws -> [String: SentenceSignals] {
        try await send { id in ScoreRequest(id: id, sentences: sentences) }.sentences ?? [:]
    }

    public func flow(_ pairs: [FlowRequest]) async throws -> [String: Signal] {
        try await send { id in FlowMessage(id: id, pairs: pairs) }.flowSentences ?? [:]
    }

    /// Writes one request line and waits for the worker's answer to that request id.
    private func send(_ make: @escaping (String) -> some Encodable) async throws -> Incoming {
        try await withCheckedThrowingContinuation { continuation in
            let sent: (FileHandle, Data)? = lock.withLock {
                guard let input, process?.isRunning == true,
                      let body = try? JSONEncoder().encode(make("r\(nextID + 1)"))
                else { return nil }
                nextID += 1
                waiting["r\(nextID)"] = continuation
                return (input, body + Data("\n".utf8))
            }
            guard let (input, line) = sent else { return continuation.resume(throwing: WorkerError.notRunning) }
            do {
                try input.write(contentsOf: line)
            } catch {
                fail(all: .exited)
            }
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            guard let message = try? JSONDecoder().decode(Incoming.self, from: line) else { continue }
            handle(message)
        }
    }

    private func handle(_ message: Incoming) {
        switch message.type {
        case "ready":
            lock.withLock { restartDelay = .seconds(1) }
            onEvent(.ready(catalogueVersion: message.catalogue_version ?? ""))
        case "progress":
            onEvent(.progress(downloaded: message.downloaded ?? 0, total: message.total ?? 0))
        case "result", "flow_result":
            if let id = message.id, let continuation = lock.withLock({ waiting.removeValue(forKey: id) }) {
                continuation.resume(returning: message)
            }
        case "error":
            let text = message.message ?? "unknown worker error"
            if let id = message.id, let continuation = lock.withLock({ waiting.removeValue(forKey: id) }) {
                continuation.resume(throwing: WorkerError.failed(text))
            } else {
                onEvent(.failed(text))
            }
        default:
            break
        }
    }

    private func terminated() {
        let (restart, delay): (Bool, Duration) = lock.withLock {
            process = nil
            input = nil
            buffer.removeAll()
            defer { restartDelay = min(restartDelay * 2, .seconds(30)) }
            return (!stopping, restartDelay)
        }
        fail(all: .exited)
        onEvent(.exited)
        guard restart else { return }
        Task {
            try? await Task.sleep(for: delay)
            guard !lock.withLock({ stopping }) else { return }
            do { try start() } catch { onEvent(.failed("Could not restart the signal worker: \(error)")) }
        }
    }

    private func fail(all error: WorkerError) {
        let continuations = lock.withLock {
            defer { waiting.removeAll() }
            return Array(waiting.values)
        }
        continuations.forEach { $0.resume(throwing: error) }
    }
}

private struct ScoreRequest: Encodable {
    let type = "score"
    let id: String
    let sentences: [SentenceRequest]
}

private struct FlowMessage: Encodable {
    let type = "flow"
    let id: String
    let pairs: [FlowRequest]
}

/// Any message from the worker. `sentences` holds full signals in a score result and a single
/// flow signal per sentence in a flow result, so it is decoded both ways.
private struct Incoming: Decodable, Sendable {
    let type: String
    let id: String?
    let catalogue_version: String?
    let downloaded: Int64?
    let total: Int64?
    let message: String?
    let sentences: [String: SentenceSignals]?
    let flowSentences: [String: Signal]?

    enum CodingKeys: String, CodingKey { case type, id, catalogue_version, downloaded, total, message, sentences }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        catalogue_version = try c.decodeIfPresent(String.self, forKey: .catalogue_version)
        downloaded = try c.decodeIfPresent(Int64.self, forKey: .downloaded)
        total = try c.decodeIfPresent(Int64.self, forKey: .total)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        sentences = type == "result" ? try c.decodeIfPresent([String: SentenceSignals].self, forKey: .sentences) : nil
        flowSentences = type == "flow_result" ? try c.decodeIfPresent([String: Signal].self, forKey: .sentences) : nil
    }
}
