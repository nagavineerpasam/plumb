import AVFoundation
import AppKit
import Observation
import WhisperKit
import WritingSignalsCore

/// Speaking into the note with Whisper (base.en on Core ML, fully on the Mac). While you talk,
/// the words since your last pause show grey and keep improving; when you pause, that stretch is
/// transcribed once more and settles into the note, where it's checked like typing.
@MainActor @Observable
final class Dictation {
    private(set) var isListening = false
    /// Whether any words have arrived since listening started (hides the "Start speaking…" prompt).
    private(set) var heardSomething = false
    /// 0...1 microphone level for the button's glow.
    private(set) var level: Double = 0
    /// Set while the voice model downloads (0..<1) and loads (1); nil otherwise.
    private(set) var preparing: Double?
    var problem: String?

    /// Words Whisper was unsure of, in note coordinates (for the "maybe misheard" hint).
    var hints: [NSRange] { buffer?.hints ?? [] }
    /// In-progress words, drawn grey.
    var grey: NSRange? { buffer?.grey }

    /// A word Whisper gives less than this probability is hinted as maybe misheard. Clearly
    /// spoken words score 0.8+ (a test sentence: "I" 0.81, "goes" 0.83, the rest 0.9+).
    static let unsureBelow = 0.35
    private static let silenceTimeout: TimeInterval = 10
    private static let rate = 16_000  // Whisper's sample rate
    /// A pause this long settles the words spoken before it.
    private static let pauseToSettle = rate * 7 / 10
    /// Whisper hears at most 30 s at once; settle before that even without a pause.
    private static let longestStretch = rate * 25
    /// Unload the model after this long without speaking, so it doesn't hold memory all day.
    private static let unloadAfter: TimeInterval = 300

    weak var textView: NSTextView?
    private var buffer: DictationBuffer?
    private var kit: WhisperKit?
    private var engine: AVAudioEngine?
    private let audio = HeardAudio()
    private var lastSound = Date()
    private var silenceTimer: Timer?
    private var unloadTimer: Timer?
    /// The current Speak session, from the click until the last words have settled.
    private var session: Task<Void, Never>?
    /// True while Plumb itself edits the text, so those edits aren't mistaken for the user's.
    private(set) var applyingEdit = false

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        // `session` is set at once, so a second click (or ⌥⌘D) while the first is still getting
        // the microphone or the model ready can't start a second session.
        guard session == nil, textView != nil else { return }
        problem = nil
        session = Task {
            await self.run()
            self.session = nil
        }
    }

    /// Stops the microphone; the words already spoken still settle.
    func stop() {
        guard isListening else { return }
        isListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        level = 0
    }

    /// A different note opened: its text has no hints.
    func reset() {
        stop()
        buffer = nil
    }

    /// The user typed while dictating: keep hint ranges and the insertion point in step.
    func userEdited(_ range: NSRange, replacementLength: Int) {
        guard !applyingEdit else { return }
        buffer?.userEdited(range, replacementLength: replacementLength)
    }

    private func run() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            problem = "Plumb needs the microphone to hear you. Turn it on in System Settings → Privacy & Security → Microphone."
            return
        }
        unloadTimer?.invalidate()
        do {
            try await loadModel()
            guard let textView else { return }
            buffer = DictationBuffer(selection: textView.selectedRange(), in: textView.string, keeping: hints)
            heardSomething = false
            audio.reset()
            isListening = true
            try startMicrophone()
            startSilenceWatch()
            try await listen()
        } catch {
            problem = "Speaking stopped: \(error.localizedDescription)"
            stop()
        }
        unloadTimer = Timer.scheduledTimer(withTimeInterval: Self.unloadAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isListening else { return }
                self.kit = nil
            }
        }
    }

    /// The first time, downloads the voice model (about 130 MB); then loads it. The very first
    /// load also prepares it for this Mac's Neural Engine, which takes a while, once.
    private func loadModel() async throws {
        guard kit == nil else { return }
        preparing = 0
        defer { preparing = nil }
        let model = VoiceModel(folder: WorkerLocation.dataFolder.appendingPathComponent("Voice", isDirectory: true))
        if !model.isInstalled {
            try await model.install(from: VoiceModel.releaseURL) { [weak self] fraction in
                Task { @MainActor in
                    if let self, let preparing = self.preparing, preparing < 1 { self.preparing = min(fraction, 0.99) }
                }
            }
        }
        preparing = 1
        kit = try await WhisperKit(WhisperKitConfig(modelFolder: model.folder.path, verbose: false, logLevel: .error,
                                                    prewarm: true, load: true, download: false))
    }

    /// Transcribes as the audio arrives until listening stops and the last words have settled.
    private func listen() async throws {
        var stream = VoiceStream(unsureBelow: Self.unsureBelow)
        var settled: [[HeardWord]] = []
        var start = 0        // first sample not yet settled
        var lastPreview = 0  // sample count at the last grey preview
        while true {
            try await Task.sleep(for: .milliseconds(200))
            let (count, lastVoice) = audio.progress
            let spoke = lastVoice > start
            let stopping = !isListening
            if spoke, stopping || count - lastVoice >= Self.pauseToSettle || count - start >= Self.longestStretch {
                let end = min(count, lastVoice + Self.rate / 4)
                let words = try await transcribe(audio.samples(start..<end), words: true).words
                start = end
                if !words.isEmpty { settled.append(words) }
                apply(&stream, settled, unconfirmed: "")
            } else if spoke, !stopping, lastVoice > lastPreview, count - lastPreview >= Self.rate / 2 {
                lastPreview = count
                let text = try await transcribe(audio.samples(start..<count), words: false).text
                if isListening { apply(&stream, settled, unconfirmed: text) }
            } else if !spoke {
                start = count  // nothing said since the last settle: skip the silence
            }
            if stopping { return }
        }
    }

    private func apply(_ stream: inout VoiceStream, _ settled: [[HeardWord]], unconfirmed: String) {
        guard var buffer else { return }
        let edits = stream.update(confirmed: settled, unconfirmed: unconfirmed, buffer: &buffer)
        self.buffer = buffer
        for edit in edits { apply(edit) }
        if !edits.isEmpty {
            heardSomething = true
            lastSound = Date()
        }
    }

    private func transcribe(_ samples: [Float], words: Bool) async throws -> (text: String, words: [HeardWord]) {
        guard let kit, samples.count > Self.rate / 4 else { return ("", []) }
        let options = DecodingOptions(task: .transcribe, language: "en", temperature: 0, skipSpecialTokens: true,
                                      withoutTimestamps: !words, wordTimestamps: words, suppressBlank: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var heard = results.flatMap(\.segments).flatMap { $0.words ?? [] }
            .map { HeardWord(text: $0.word, probability: Double($0.probability)) }
        if heard.isEmpty, !text.isEmpty { heard = [HeardWord(text: text, probability: 1)] }
        return (text, heard)
    }

    /// Applies one buffer edit to the text view as a normal, undoable text change.
    private func apply(_ edit: DictationBuffer.Edit) {
        guard let textView else { return }
        applyingEdit = true
        defer { applyingEdit = false }
        if textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textView.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        let end = edit.range.location + (edit.replacement as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    private func startMicrophone() throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        guard let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.rate),
                                                channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: micFormat, to: whisperFormat) else {
            throw DictationError.noAudioFormat
        }
        let onLevel: @Sendable (Double) -> Void = { [weak self] rms in
            Task { @MainActor in
                self?.level = min(1, rms * 12)
                if rms > HeardAudio.voiceLevel { self?.lastSound = Date() }
            }
        }
        node.installTap(onBus: 0, bufferSize: 1024, format: micFormat,
                        block: Self.tap(converter: converter, to: whisperFormat, from: micFormat,
                                        into: audio, onLevel: onLevel))
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// The audio callback runs on the audio thread, so it is built outside the main actor:
    /// it converts each buffer to 16 kHz mono for Whisper and reports the level to the main thread.
    nonisolated private static func tap(converter: AVAudioConverter, to format: AVAudioFormat,
                                        from micFormat: AVAudioFormat, into audio: HeardAudio,
                                        onLevel: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let level = rms(buffer)
            onLevel(level)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / micFormat.sampleRate) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard let data = out.floatChannelData?[0] else { return }
            audio.append(UnsafeBufferPointer(start: data, count: Int(out.frameLength)), voiced: level > HeardAudio.voiceLevel)
        }
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

/// The 16 kHz audio heard since Speak was clicked, written by the audio thread and read by the
/// transcription loop, plus where the voice was last heard.
final class HeardAudio: @unchecked Sendable {
    /// Microphone level above which the audio counts as someone speaking.
    static let voiceLevel = 0.01
    private let lock = NSLock()
    private var all: [Float] = []
    private var lastVoice = 0

    func append(_ chunk: UnsafeBufferPointer<Float>, voiced: Bool) {
        lock.withLock {
            all.append(contentsOf: chunk)
            if voiced { lastVoice = all.count }
        }
    }

    /// How many samples have arrived, and the end of the last one with voice in it.
    var progress: (count: Int, lastVoice: Int) { lock.withLock { (all.count, lastVoice) } }

    func samples(_ range: Range<Int>) -> [Float] { lock.withLock { Array(all[range.clamped(to: 0..<all.count)]) } }

    func reset() { lock.withLock { all.removeAll(); lastVoice = 0 } }
}

enum DictationError: LocalizedError {
    case noAudioFormat
    var errorDescription: String? { "the microphone's audio format can't be converted for Whisper" }
}
