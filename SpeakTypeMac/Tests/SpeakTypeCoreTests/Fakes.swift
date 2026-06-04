@testable import SpeakTypeCore

// Fake ports for deterministic coordinator tests.

final class FakeAudioCapture: AudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var nextCapture = CapturedAudio(samples: [0.1, 0.2, 0.3], hasSpeech: true)
    func start() { startCount += 1 }
    func stop() -> CapturedAudio { stopCount += 1; return nextCapture }
}

// @unchecked Sendable: tests only touch it across `await` suspension points (which
// establish ordering), so the mutable counters are race-free in practice.
final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private(set) var callCount = 0
    var result = "hello world"
    func transcribe(_ samples: [Float]) async -> String { callCount += 1; return result }
}

final class FakePaste: Pasting {
    private(set) var pasted: [String] = []
    var outcome: PasteOutcome = .pasted
    func paste(_ text: String) -> PasteOutcome { pasted.append(text); return outcome }
}

/// Records the text delivered and returns a configurable outcome — lets a test drive the
/// coordinator's destination without a real paste/note.
final class FakeSink: DictationSink {
    private(set) var delivered: [String] = []
    var outcome: DictationOutcome = .pasted
    func deliver(_ text: String) -> DictationOutcome { delivered.append(text); return outcome }
}

/// Tick == milliseconds. Tests set `ticksMs` to simulate the press→release hold.
final class FakeClock: MonotonicClock {
    var ticksMs: UInt64 = 0
    func timestamp() -> UInt64 { ticksMs }
    func elapsed(since start: UInt64) -> Duration { .milliseconds(Int(ticksMs - start)) }
}

final class FakeAutoStopTimer: AutoStopTimer {
    private(set) var startedDelay: Duration?
    private(set) var cancelCount = 0
    func start(after delay: Duration, onElapsed: @escaping @Sendable () -> Void) { startedDelay = delay }
    func cancel() { cancelCount += 1 }
}
