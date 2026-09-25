import AVFoundation
import AppKit
import Observation
import Speech
import WritingSignalsCore

/// Speaking into the note: the microphone feeds Apple's on-device recognizer, and each result
/// becomes an edit at the cursor through DictationBuffer, exactly as if it had been typed.
@MainActor @Observable
final class Dictation {
    private(set) var isListening = false
    /// 0...1 microphone level for the button's glow.
    private(set) var level: Double = 0
    var problem: String?

    /// Words the recognizer was unsure of, in note coordinates (for the "say this more clearly" hint).
    var hints: [NSRange] { buffer?.hints ?? [] }
    /// In-progress words, drawn grey.
    var grey: NSRange? { buffer?.grey }

    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true } else { return false }
    }

    /// Confidence below this marks a word as unsure. Chosen from real recognizer output (ticket 20).
    static let unsureBelow = 0.5
    private static let silenceTimeout: TimeInterval = 10

    weak var textView: NSTextView?
    private var buffer: DictationBuffer?
    private var engine: AVAudioEngine?
    /// Ends the audio stream so the recognizer finishes its last phrase.
    private var finishInput: (() -> Void)?
    private var session: Task<Void, Never>?
    private var lastSound = Date()
    private var silenceTimer: Timer?
    /// True while Plumb itself edits the text, so those edits aren't mistaken for the user's.
    private(set) var applyingEdit = false

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening, let textView else { return }
        guard #available(macOS 26, *) else { return }
        problem = nil
        buffer = DictationBuffer(selection: textView.selectedRange(), in: textView.string)
        isListening = true
        session = Task { await self.run() }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        finishInput?()
        finishInput = nil
        level = 0
    }

    /// The user typed while dictating: keep hint ranges and the insertion point in step.
    func userEdited(_ range: NSRange, replacementLength: Int) {
        guard !applyingEdit else { return }
        buffer?.userEdited(range, replacementLength: replacementLength)
    }

    @available(macOS 26, *)
    private func run() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            problem = "Plumb needs the microphone to hear you. Turn it on in System Settings → Privacy & Security → Microphone."
            stop()
            return
        }
        do {
            let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [.transcriptionConfidence])
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()  // once, the first time
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw DictationError.noAudioFormat
            }
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            finishInput = { continuation.finish() }
            try startMicrophone(feeding: continuation, as: format)
            try await analyzer.start(inputSequence: stream)
            startSilenceWatch()

            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    var unsure: [NSRange] = []
                    for run in result.text.runs where (run.transcriptionConfidence ?? 1) < Self.unsureBelow {
                        unsure.append(NSRange(run.range, in: result.text))
                    }
                    apply { $0.final(text.trimmingCharacters(in: .whitespaces), unsure: unsure) }
                } else {
                    apply { $0.volatile(text.trimmingCharacters(in: .whitespaces)) }
                }
                lastSound = Date()
            }
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            problem = "Dictation stopped: \(error.localizedDescription)"
        }
        stop()
    }

    /// Applies one buffer edit to the text view as a normal, undoable text change.
    private func apply(_ step: (inout DictationBuffer) -> DictationBuffer.Edit) {
        guard var buffer, let textView else { return }
        let edit = step(&buffer)
        self.buffer = buffer
        applyingEdit = true
        defer { applyingEdit = false }
        if textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textView.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        let end = edit.range.location + (edit.replacement as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    @available(macOS 26, *)
    private func startMicrophone(feeding continuation: AsyncStream<AnalyzerInput>.Continuation,
                                 as format: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: micFormat, to: format)
        node.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { [weak self] buffer, _ in
            let rms = Self.rms(buffer)
            Task { @MainActor in
                self?.level = min(1, rms * 12)
                if rms > 0.01 { self?.lastSound = Date() }
            }
            guard let converter else { return }
            let ratio = format.sampleRate / micFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            continuation.yield(AnalyzerInput(buffer: out))
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func startSilenceWatch() {
        lastSound = Date()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                if Date().timeIntervalSince(self.lastSound) > Self.silenceTimeout { self.stop() }
            }
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return Double((sum / Float(buffer.frameLength)).squareRoot())
    }
}

enum DictationError: LocalizedError {
    case noAudioFormat
    var errorDescription: String? { "no audio format the recognizer accepts" }
}
