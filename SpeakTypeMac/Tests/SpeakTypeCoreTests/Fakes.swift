import Foundation
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

/// In-memory NotesPersisting: seeds the store on load and records what it saved.
final class FakeNotesPersistence: NotesPersisting, @unchecked Sendable {
    var stored: [Note]
    private(set) var saveCount = 0
    private(set) var lastSaved: [Note] = []
    init(_ initial: [Note] = []) { stored = initial }
    func load() -> [Note] { stored }
    func save(_ notes: [Note]) { saveCount += 1; lastSaved = notes; stored = notes }
}

/// Monotonic date source so updatedAt ordering is deterministic (each call is one second later).
final class FakeDates {
    private var seconds: TimeInterval = 0
    func next() -> Date { seconds += 1; return Date(timeIntervalSinceReferenceDate: seconds) }
}

/// In-memory ShelfPersisting: seeds the store on load and records what it saved.
final class FakeShelfPersistence: ShelfPersisting, @unchecked Sendable {
    var stored: [ShelfItem]
    private(set) var saveCount = 0
    private(set) var lastSaved: [ShelfItem] = []
    init(_ initial: [ShelfItem] = []) { stored = initial }
    func load() -> [ShelfItem] { stored }
    func save(_ items: [ShelfItem]) { saveCount += 1; lastSaved = items; stored = items }
}

/// Records which items' payload bytes the store asked to delete.
final class FakeShelfPayloadStore: ShelfPayloadStore, @unchecked Sendable {
    private(set) var deleted: [ShelfItem] = []
    func delete(_ items: [ShelfItem]) { deleted.append(contentsOf: items) }
}
