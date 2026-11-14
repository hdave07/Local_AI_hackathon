import Argmax
import FlowAudio
import Foundation

/// Settings for the Argmax Pro streaming recognizer.
public struct ArgmaxSettings: Sendable {
    public enum Input: Sendable {
        /// Live capture. `nil` = system default input device.
        case microphone(deviceID: DeviceID?)
        /// Replays an audio file through the same streaming pipeline (fixtures, tests).
        /// Trailing silence is appended so the recognizer can confirm the last words.
        case file(URL, realtime: Bool, trailingSilence: TimeInterval)
    }

    /// Argmax runtime key (`ax_…`). Read from the environment; never hardcode.
    public var apiKey: String?
    /// HuggingFace token, only if the model repository requires one.
    public var huggingFaceToken: String?
    /// Real-time English model recommended by Argmax.
    public var model: String
    public var repo: RepoType
    public var input: Input
    public var streamMode: StreamTranscriptionMode
    public var transcribeInterval: Double
    /// Where Flow ends one utterance's recognizer stream (see `UtteranceSegmenter`).
    public var segmentPolicy: UtteranceSegmenter.Policy
    public var verbose: Bool

    public init(
        apiKey: String?,
        huggingFaceToken: String? = nil,
        model: String = "parakeet-v2_476MB",
        repo: RepoType = .parakeetRepo,
        input: Input = .microphone(deviceID: nil),
        streamMode: StreamTranscriptionMode = .voiceTriggered,
        transcribeInterval: Double = 0.1,
        segmentPolicy: UtteranceSegmenter.Policy = UtteranceSegmenter.Policy(),
        verbose: Bool = false
    ) {
        self.apiKey = apiKey
        self.huggingFaceToken = huggingFaceToken
        self.model = model
        self.repo = repo
        self.input = input
        self.streamMode = streamMode
        self.transcribeInterval = transcribeInterval
        self.segmentPolicy = segmentPolicy
        self.verbose = verbose
    }

    /// Reads `ARGMAX_API_KEY` / `HF_TOKEN` via the SDK's `EnvKeyProvider`.
    public static func fromEnvironment(input: Input = .microphone(deviceID: nil)) -> ArgmaxSettings {
        let env = EnvKeyProvider()
        return ArgmaxSettings(apiKey: env.apiKey, huggingFaceToken: env.huggingFaceToken, input: input)
    }

    public var usesMicrophone: Bool {
        if case .microphone = input { true } else { false }
    }
}

/// Timings and SDK facts recorded during `prepare()`, for evidence and the HUD.
public struct ArgmaxDiagnostics: Sendable {
    public var sdkVersion: String
    public var modelFolder: URL?
    public var downloadDuration: Duration?
    public var loadDuration: Duration?
    public var lastLicenseEvent: String?
}

/// `SpeechTranscribing` backed by Argmax Pro `LiveTranscriber` (SDK 3.1.8).
///
/// Confirmed text maps to `.confirmed`, hypothesis text to `.hypothesis` (display only).
/// VAD transitions come from the SDK's relative-energy measure on each audio chunk,
/// using the same silence threshold as `StreamTranscriptionMode.voiceTriggered`.
///
/// The microphone is opened once; each utterance gets its own SDK stream, ended by
/// `UtteranceSegmenter` after speech stops so the SDK confirms its final words
/// (3.1.8 does not confirm during continued silence). Audio is never written to disk.
public actor ArgmaxTranscriber: SpeechTranscribing {
    public nonisolated let capabilities = TranscriberCapabilities(
        interimHypotheses: true,
        voiceActivityEvents: true,
        // Supported by the SDK for Parakeet only, via an extra model; not wired yet.
        customVocabulary: false)

    public let settings: ArgmaxSettings
    public private(set) var diagnostics = ArgmaxDiagnostics(sdkVersion: ArgmaxSDK.sdkVersion)

    private var whisperKit: WhisperKitPro?
    private var router: Task<Void, Never>?
    private var feeder: Task<Void, Never>?
    private var audioContinuation: TranscriptionInputStream.Continuation?
    private let licenseLog = LockedValue<String?>(nil)

    public init(settings: ArgmaxSettings) {
        self.settings = settings
    }

    public func prepare() async throws(AudioError) {
        if whisperKit != nil { return }
        guard let key = settings.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw .licenseMissing
        }

        let config = ArgmaxConfig(apiKey: key)
        config.keychainPersistence = false
        let log = licenseLog
        config.licenseStatusCallback = { update in
            log.set("\(update.licenseEvent) → \(update.result.rawValue)")
        }
        await ArgmaxSDK.with(config)

        let clock = ContinuousClock()
        let downloadStart = clock.now
        let folder: URL
        do {
            folder = try await ModelStore().downloadModel(
                name: settings.model, repo: settings.repo, token: settings.huggingFaceToken)
        } catch {
            throw Self.map(error, during: .download)
        }
        diagnostics.downloadDuration = clock.now - downloadStart
        diagnostics.modelFolder = folder

        let loadStart = clock.now
        do {
            let proConfig = WhisperKitProConfig(
                model: settings.model,
                modelRepo: settings.repo.rawValue,
                modelFolder: folder.path,
                verbose: settings.verbose,
                logLevel: settings.verbose ? .debug : .error,
                load: true,
                download: false)
            whisperKit = try await WhisperKitPro(proConfig)
        } catch {
            diagnostics.lastLicenseEvent = licenseLog.get()
            throw Self.map(error, during: .load)
        }
        diagnostics.loadDuration = clock.now - loadStart
        diagnostics.lastLicenseEvent = licenseLog.get()
    }

    public func start() async throws(AudioError) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        guard router == nil else { throw .alreadyRunning }
        if whisperKit == nil { try await prepare() }
        guard let whisperKit else { throw .engineFailed("recognizer not loaded") }

        // One continuous audio source for the whole session.
        let audio: TranscriptionInputStream
        switch settings.input {
        case .microphone(let deviceID):
            let (stream, continuation) = whisperKit.audioProcessor.startStreamingRecordingLive(inputDeviceID: deviceID)
            audio = stream
            audioContinuation = continuation
        case .file(let url, let realtime, let trailingSilence):
            let samples: [Float]
            do {
                samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            } catch {
                throw .engineFailed("could not read audio file: \(error.localizedDescription)")
            }
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Float].self, throwing: (any Error).self)
            audio = stream
            audioContinuation = continuation
            feeder = Task {
                await Self.feed(samples, trailingSilence: trailingSilence, realtime: realtime, into: continuation)
            }
        }

        let live = LiveTranscriber(whisperKit: whisperKit)
        let options = DecodingOptionsPro(
            base: DecodingOptions(task: .transcribe, wordTimestamps: true, chunkingStrategy: .vad),
            transcribeInterval: settings.transcribeInterval,
            streamTranscriptionMode: settings.streamMode,
            alignTimestampsToGlobal: true)

        // Open the first recognizer segment here so setup failures surface from start().
        let first: Segment
        do {
            first = try await Segment.open(live, options: options)
        } catch {
            stopCapture()
            throw Self.map(error, during: .stream)
        }

        let (events, continuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self, throwing: (any Error).self)
        let segmenter = UtteranceSegmenter(
            vad: EnergyVoiceActivityDetector(threshold: Self.silenceThreshold(settings.streamMode)),
            policy: settings.segmentPolicy)
        router = Task {
            await Self.route(audio: audio, first: first, live: live, options: options, segmenter: segmenter, events: continuation)
        }
        return events
    }

    public func stop() async {
        stopCapture()
        // Ending the input makes the router flush the last segment, then finish events.
        await router?.value
        router = nil
    }

    private func stopCapture() {
        feeder?.cancel()
        feeder = nil
        audioContinuation?.finish()
        audioContinuation = nil
        if case .microphone = settings.input { whisperKit?.audioProcessor.stopRecording() }
    }

    /// One recognizer stream covering one utterance.
    struct Segment {
        let source: CustomSource
        let input: TranscriptionInputStream.Continuation
        let results: TranscriptionOutputStream

        static func open(_ live: LiveTranscriber, options: DecodingOptionsPro) async throws -> Segment {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Float].self, throwing: (any Error).self)
            let source = CustomSource(id: "segment-\(UUID().uuidString)", audioStream: stream, audioContinuation: continuation)
            try await live.registerStream(streamSource: source, options: options)
            let results = try await live.startTranscription(for: source)
            return Segment(source: source, input: continuation, results: results)
        }
    }

    /// Feeds audio to the current segment, emits VAD transitions, and ends a segment
    /// when the utterance is over so the SDK confirms its text. Segment results are
    /// forwarded strictly in order, each followed by `.endOfSegment`.
    static func route(
        audio: TranscriptionInputStream, first: Segment, live: LiveTranscriber, options: DecodingOptionsPro,
        segmenter: UtteranceSegmenter, events: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation
    ) async {
        var segment = first
        var segmenter = segmenter
        var forwarder = forward(segment.results, after: nil, to: events)
        do {
            for try await chunk in audio {
                guard !chunk.isEmpty else { continue }
                let level = AudioProcessor.calculateRelativeEnergy(of: chunk, relativeTo: nil)
                let step = segmenter.process(level: level, duration: Double(chunk.count) / 16_000)
                if let activity = step.activity { events.yield(.voiceActivity(activity)) }
                segment.input.yield(chunk)
                if step.cut {
                    try? await live.stopAndRemoveStream(for: segment.source)  // flush → confirm
                    segment = try await Segment.open(live, options: options)
                    forwarder = forward(segment.results, after: forwarder, to: events)
                }
            }
            try? await live.stopAndRemoveStream(for: segment.source)
            await forwarder.value
            events.finish()
        } catch {
            try? await live.stopAndRemoveAllTranscriptions()
            await forwarder.value
            events.finish(throwing: map(error, during: .stream))
        }
    }

    static func forward(
        _ results: TranscriptionOutputStream, after previous: Task<Void, Never>?,
        to events: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation
    ) -> Task<Void, Never> {
        Task {
            await previous?.value  // results buffer meanwhile; ordering is preserved
            do {
                for try await result in results {
                    switch result {
                    case .confirm(let text, _, let result):
                        events.yield(.confirmed(text, language: result.language))
                    case .hypothesis(let text, _, _):
                        events.yield(.hypothesis(text))
                    }
                }
                events.yield(.endOfSegment)
            } catch {
                events.finish(throwing: map(error, during: .stream))
            }
        }
    }

    // MARK: - Helpers

    enum Phase { case download, load, stream }

    /// Maps SDK errors to Flow's typed errors without losing the SDK's message.
    static func map(_ error: any Error, during phase: Phase) -> AudioError {
        if let audio = error as? AudioError { return audio }
        if error is CancellationError { return .cancelled }
        if let argmax = error as? ArgmaxError {
            switch argmax {
            case .invalidLicense(let message):
                return .licenseRejected(message)
            case .modelUnavailable(let message, _):
                return .modelUnavailable(message)
            case .invalidConfiguration(let message):
                return phase == .stream ? .engineFailed(message) : .modelUnavailable(message)
            case .generic(let message):
                // LiveTranscriber reports a refused microphone as a generic error.
                if message.localizedCaseInsensitiveContains("permission") { return .microphoneDenied }
                return phase == .download ? .modelUnavailable(message) : .engineFailed(message)
            case .invalidModelOutput(let message):
                return .engineFailed(message)
            @unknown default:
                return .engineFailed(argmax.localizedDescription)
            }
        }
        if let live = error as? LiveTranscriberError {
            return .engineFailed(String(describing: live))
        }
        let message = (error as NSError).localizedDescription
        return phase == .stream ? .engineFailed(message) : .modelUnavailable(message)
    }

    static func silenceThreshold(_ mode: StreamTranscriptionMode) -> Float {
        if case .voiceTriggered(let threshold, _, _) = mode { return threshold }
        return StreamTranscriptionMode.defaultSilenceThreshold
    }

    /// Pushes file audio in 100 ms chunks, then silence, then ends the input.
    static func feed(
        _ samples: [Float], trailingSilence: TimeInterval, realtime: Bool,
        into continuation: TranscriptionInputStream.Continuation
    ) async {
        let chunk = 1_600
        let silence = [Float](repeating: 0, count: Int(trailingSilence * 16_000))
        let all = samples + silence
        var index = 0
        while index < all.count, !Task.isCancelled {
            let end = min(index + chunk, all.count)
            continuation.yield(Array(all[index..<end]))
            index = end
            if realtime { try? await Task.sleep(for: .milliseconds(100)) }
        }
        continuation.finish()
    }
}

/// Minimal lock-protected box for state shared with SDK callbacks.
final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func get() -> Value { lock.withLock { value } }
    func set(_ new: Value) { lock.withLock { value = new } }
    func update<R>(_ body: (inout Value) -> R) -> R { lock.withLock { body(&value) } }
}

/// SDK facts for callers that should not import the SDK directly.
public enum ArgmaxTranscriberInfo {
    public static var sdkVersion: String { ArgmaxSDK.sdkVersion }
    public static var defaultSilenceThreshold: Float { StreamTranscriptionMode.defaultSilenceThreshold }
}
