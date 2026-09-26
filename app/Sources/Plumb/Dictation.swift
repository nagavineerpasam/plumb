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
    /// True while voice is being set up for the very first time (download plus the one-time
    /// preparation for this Mac), so the note can explain it's a one-off.
    private(set) var settingUpFirstTime = false
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
        settingUpFirstTime = !model.isInstalled
        defer { settingUpFirstTime = false }
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
        var voicedAtStart = 0
        var lastPreview = 0  // sample count at the last grey preview
        while true {
            try await Task.sleep(for: .milliseconds(200))
            let (count, lastVoice, voiced) = audio.progress
            // A quarter second of speech at least: a click or a cough isn't worth transcribing, and
            // Whisper tends to "hear" words like "you" in them.
            let spoke = lastVoice > start && voiced - voicedAtStart >= Self.rate / 4
            let stopping = !isListening
            if spoke, stopping || count - lastVoice >= Self.pauseToSettle || count - start >= Self.longestStretch {
                let end = min(count, lastVoice + Self.rate / 4)
                let words = try await transcribe(audio.samples(start..<end), words: true).words
                start = end
                voicedAtStart = voiced
                if !words.isEmpty { settled.append(words) }
                apply(&stream, settled, unconfirmed: "")
            } else if spoke, !stopping, lastVoice > lastPreview, count - lastPreview >= Self.rate / 2 {
                lastPreview = count
                let text = try await transcribe(audio.samples(start..<count), words: false).text
                if isListening { apply(&stream, settled, unconfirmed: text) }
            } else if !spoke, count > Self.rate, count - lastVoice > Self.pauseToSettle {
                start = count  // nothing said since the last settle: skip the silence (after the first
                voicedAtStart = voiced  // second, whose audio is kept in case speech started at once)
            }
            if stopping { return }
        }
    }

    private func apply(_ stream: inout VoiceStream, _ settled: [[HeardWord]], unconfirmed: String) {
        guard var buffer else { return }
        let edits = stream.update(confirmed: settled, unconfirmed: unconfirmed, buffer: &buffer)
        self.buffer = buffer
        for edit in edits { apply(edit) }
        if !edits.isEmpty { lastSound = Date() }
        // The centred "Listening" stays until real words are showing (not a phantom that vanished).
        heardSomething = buffer.showsWords
    }

    private func transcribe(_ samples: [Float], words: Bool) async throws -> (text: String, words: [HeardWord]) {
        guard let kit, samples.count > Self.rate / 4 else { return ("", []) }
        let options = DecodingOptions(task: .transcribe, language: "en", temperature: 0, skipSpecialTokens: true,
                                      withoutTimestamps: !words, wordTimestamps: words, suppressBlank: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let segments = results.flatMap(\.segments)
        let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var heard = segments.flatMap { $0.words ?? [] }
            .map { HeardWord(text: $0.word, probability: Double($0.probability)) }
        // No word timings: keep the text as one word, minus any silence tags so real words survive.
        let spoken = VoiceStream.withoutTags(text).trimmingCharacters(in: .whitespaces)
        if heard.isEmpty, !spoken.isEmpty { heard = [HeardWord(text: spoken, probability: 1)] }
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
        let onLevel: @Sendable (Double, Bool) -> Void = { [weak self] rms, voiced in
            Task { @MainActor in
                self?.level = min(1, rms * 12)
                if voiced { self?.lastSound = Date() }
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
                                        onLevel: @escaping @Sendable (Double, Bool) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let level = rms(buffer)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / micFormat.sampleRate) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            let samples = out.floatChannelData.map { UnsafeBufferPointer(start: $0[0], count: Int(out.frameLength)) }
            onLevel(level, audio.append(samples ?? UnsafeBufferPointer(start: nil, count: 0), level: level))
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
    private let lock = NSLock()
    private var all: [Float] = []
    private var lastVoice = 0
    private var activity = VoiceActivity()
    /// Samples judged to be speech so far, to tell a real word from a blip of noise.
    private var voiced = 0
    /// Buffers heard while the room was still being measured, judged again once it's known.
    private var early: [(level: Double, end: Int, length: Int)] = []

    /// Adds a buffer at microphone level `level`; returns whether it sounded like speech.
    func append(_ chunk: UnsafeBufferPointer<Float>, level: Double) -> Bool {
        lock.withLock {
            all.append(contentsOf: chunk)
            let measuring = activity.sounds(level) == nil
            let isVoice = activity.hears(level)
            if isVoice { lastVoice = all.count; voiced += chunk.count }
            if measuring {
                if !isVoice { early.append((level, all.count, chunk.count)) }
                if activity.sounds(level) != nil {  // the room is known now: a quiet early word counts too
                    for buffer in early where activity.sounds(buffer.level) == true {
                        lastVoice = max(lastVoice, buffer.end)
                        voiced += buffer.length
                    }
                    early = []
                }
            }
            return isVoice
        }
    }

    /// How many samples have arrived, the end of the last one with voice in it, and how many were voice.
    var progress: (count: Int, lastVoice: Int, voiced: Int) { lock.withLock { (all.count, lastVoice, voiced) } }

    func samples(_ range: Range<Int>) -> [Float] { lock.withLock { Array(all[range.clamped(to: 0..<all.count)]) } }

    func reset() { lock.withLock { all.removeAll(); lastVoice = 0; voiced = 0; early = []; activity = VoiceActivity() } }
}

enum DictationError: LocalizedError {
    case noAudioFormat
    var errorDescription: String? { "the microphone's audio format can't be converted for Whisper" }
}
