/// Outcome of one dictation cycle, for the UI to surface.
public enum DictationOutcome: Sendable, Equatable {
    case pasted
    case leftOnClipboard
    case addedToNote
    case noSpeech
}

/// The dictation state machine — a port of the C# `DictationOrchestrator`.
///
/// Fn press → start capture + arm the 60 s auto-stop. Fn release (or auto-stop) → if the
/// hold was long enough, run capture → transcribe → clean → paste and report the outcome;
/// a too-short hold is discarded as an accidental tap. A press that arrives while a cycle
/// is in flight is ignored (the state guard).
///
/// Isolated to `@MainActor`, so the hotkey callback, the auto-stop timer hop, and the
/// async transcribe all run in one serialized domain — no locks needed. The atomic
/// "claim" that stops a release and the auto-stop from both running the cycle is just the
/// synchronous `guard state == .recording` followed (with no `await` between) by the state
/// transition: only the first caller observes `.recording`.
@MainActor
public final class DictationCoordinator {
    // Hold-duration guards (mirrors the C# values).
    private static let minHold: Duration = .milliseconds(300)
    private static let maxHold: Duration = .seconds(60)

    private let audio: AudioCapturing
    private let transcriber: Transcribing
    private let sink: DictationSink
    private let cleaner: TranscriptCleaner
    private let clock: MonotonicClock
    private let autoStop: AutoStopTimer
    private let settings: Settings

    /// Raised on each UI-meaningful state transition (recording / transcribing / pasting / idle).
    public var onStateChanged: ((DictationState) -> Void)?
    /// Raised once at the end of every cycle that produced an outcome (not for discarded taps).
    public var onCompleted: ((DictationOutcome) -> Void)?

    private var state: DictationState = .idle
    private var pressTimestamp: UInt64 = 0

    public init(
        audio: AudioCapturing,
        transcriber: Transcribing,
        sink: DictationSink,
        cleaner: TranscriptCleaner = TranscriptCleaner(),
        clock: MonotonicClock,
        autoStop: AutoStopTimer,
        settings: Settings = Settings()
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.sink = sink
        self.cleaner = cleaner
        self.clock = clock
        self.autoStop = autoStop
        self.settings = settings
    }

    public var currentState: DictationState { state }

    /// Fn went down. Begin recording unless a cycle is already in flight.
    public func pressed() {
        guard state == .idle else { return }
        pressTimestamp = clock.timestamp()
        audio.start()
        autoStop.start(after: Self.maxHold) { [weak self] in
            Task { @MainActor in await self?.autoStopFired() }
        }
        setState(.recording)
    }

    /// Fn came up. Run the cycle if the hold was long enough; otherwise discard the tap.
    public func released() async {
        autoStop.cancel()
        guard state == .recording else { return } // not recording, or auto-stop already claimed it
        let hold = clock.elapsed(since: pressTimestamp)
        guard hold >= Self.minHold else {
            discard() // accidental tap (< 300 ms)
            return
        }
        setState(.transcribing)
        await runCycle()
    }

    /// 60 s reached while still held — end the hold the same as a release.
    public func autoStopFired() async {
        guard state == .recording else { return }
        setState(.transcribing)
        await runCycle()
    }

    /// Aborts an in-progress recording and returns to idle, discarding the audio (no
    /// transcribe, no paste, no outcome). Used when the hold is cancelled mid-press (e.g.
    /// Fn used as a modifier). No-op unless currently recording, so it never interrupts a
    /// running cycle.
    public func cancel() {
        guard state == .recording else { return }
        autoStop.cancel()
        _ = audio.stop() // discard the audio
        setState(.idle)
    }

    private func runCycle() async {
        let captured = audio.stop()
        guard captured.hasSpeech else { return finish(.noSpeech) }

        let raw = await transcriber.transcribe(captured.samples)
        let cleaned = cleaner.clean(raw, removeFillers: settings.fillerRemoval)
        guard !cleaned.isEmpty else { return finish(.noSpeech) }

        setState(.pasting)
        finish(sink.deliver(cleaned))
    }

    private func discard() {
        _ = audio.stop() // release the mic, throw the audio away
        setState(.idle)
    }

    private func finish(_ outcome: DictationOutcome) {
        setState(.idle)
        onCompleted?(outcome)
    }

    private func setState(_ newState: DictationState) {
        state = newState
        onStateChanged?(newState)
    }
}
