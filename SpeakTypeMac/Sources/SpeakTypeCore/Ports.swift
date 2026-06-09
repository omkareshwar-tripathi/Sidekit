import Foundation

// The "ports" of the ports-and-adapters design: the pure core (the coordinator,
// brick MAC-2) depends only on these protocols and value types, never on system
// frameworks. Native adapters (AVAudioEngine, CGEvent, WhisperKit) implement them in
// the SpeakTypeApp target. This mirrors the C# app's IAudioCapture / IHotkeyListener /
// IPasteService / ITranscriber.

/// Captured 16 kHz mono audio. `hasSpeech` is the adapter's RMS silence-gate verdict;
/// `false` means near-silent and the cycle should skip transcription.
public struct CapturedAudio: Sendable, Equatable {
    public let samples: [Float]
    public let hasSpeech: Bool

    public init(samples: [Float], hasSpeech: Bool) {
        self.samples = samples
        self.hasSpeech = hasSpeech
    }
}

/// Result of a paste attempt. `.leftOnClipboard` means the keystroke could not be
/// delivered, so the text was left on the clipboard rather than silently lost.
public enum PasteOutcome: Sendable, Equatable {
    case pasted
    case leftOnClipboard
}

/// UI-meaningful states of one dictation cycle.
public enum DictationState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case pasting
}

/// Microphone capture port. `start()` opens the mic; `stop()` ends capture and returns
/// the buffer. Start/stop are never overlapped by the coordinator.
public protocol AudioCapturing: AnyObject {
    func start()
    func stop() -> CapturedAudio
}

/// Push-to-talk source. `onPressed` fires when the key goes down, `onReleased` when it
/// comes back up, and `onCancelled` when the hold is aborted (e.g. another key was pressed
/// while Fn was held — Fn used as a modifier, not for dictation).
public protocol HotkeyListening: AnyObject {
    var onPressed: (() -> Void)? { get set }
    var onReleased: (() -> Void)? { get set }
    var onCancelled: (() -> Void)? { get set }
}

/// Inserts text into the focused application, or leaves it on the clipboard.
public protocol Pasting: AnyObject {
    func paste(_ text: String) -> PasteOutcome
}

/// Destination for a finished, cleaned transcript. The coordinator hands the text here and
/// reports the returned outcome; it stays unaware of clipboards, windows, or notes. The app
/// supplies the implementation (paste-at-cursor today; route-to-focused-note later).
public protocol DictationSink: AnyObject {
    func deliver(_ text: String) -> DictationOutcome
}

/// Turns 16 kHz mono samples into a transcript. Async because WhisperKit is async, and
/// `Sendable` because the coordinator calls it from the main actor but the work runs
/// off-main (so it never blocks the UI).
public protocol Transcribing: Sendable {
    func transcribe(_ samples: [Float]) async -> String
}

/// Loads and saves the scratchpad notes. The store calls `load()` once at init and `save(_:)`
/// after every mutation; the adapter (UI-3) backs this with a JSON file. `flush()` forces any
/// buffered/debounced write to disk immediately (called on app termination).
public protocol NotesPersisting: Sendable {
    func load() -> [Note]
    func save(_ notes: [Note])
    func flush()
}

public extension NotesPersisting {
    /// Default: nothing is buffered, so there's nothing to flush. A debouncing adapter overrides.
    func flush() {}
}

/// Loads and saves the Shelf's item index (metadata only — the payload bytes are a separate
/// adapter concern). The store calls `load()` once at init and `save(_:)` after every mutation.
public protocol ShelfPersisting: Sendable {
    func load() -> [ShelfItem]
    func save(_ items: [ShelfItem])
    func flush()
}

public extension ShelfPersisting {
    /// Default: nothing is buffered, so there's nothing to flush. A debouncing adapter overrides.
    func flush() {}
}

/// A thing dropped onto the shelf, to be copied into the store: a file/folder on disk, a text
/// snippet, or image bytes. (AppKit's `NSItemProvider` decode happens in the UI; this is the pure
/// hand-off.)
public enum ShelfPayloadSource: Sendable {
    case file(URL)
    case text(String)
    case image(Data)
}

/// Where a copied payload landed plus the metadata `ShelfStore` records for it. The payload store
/// owns the byte copy and reports back the kind/name/size/location.
public struct StoredPayload: Sendable, Equatable {
    public let kind: ShelfItemKind
    public let displayName: String
    public let byteSize: Int64
    public let storedRelativePath: String

    public init(kind: ShelfItemKind, displayName: String, byteSize: Int64, storedRelativePath: String) {
        self.kind = kind
        self.displayName = displayName
        self.byteSize = byteSize
        self.storedRelativePath = storedRelativePath
    }
}

public enum ShelfPayloadStoreError: Error { case unsupported }

/// Owns the on-disk payload bytes for shelved items (a copy under the app container). The index
/// (`ShelfPersisting`) holds metadata; this holds the actual files. `store(_:)` copies a dropped
/// source in (drag-in); `delete(_:)` removes bytes whenever items leave (per-item remove, clear-all,
/// or expiry) so bytes never outlive their index entry. Deletion is best-effort.
public protocol ShelfPayloadStore: Sendable {
    /// Copy a dropped source's bytes into a fresh per-item folder and return where they landed.
    /// Throws if the copy fails — the caller then records nothing.
    func store(_ source: ShelfPayloadSource) throws -> StoredPayload
    /// The on-disk location of an item's stored bytes (drives tile QuickLook thumbnails), or nil when
    /// this store holds no bytes (the noop store) so callers fall back to a placeholder.
    func url(for item: ShelfItem) -> URL?
    /// Whether `url` points inside this store's payload area — lets a drop ignore a drag-out that was
    /// released back onto the shelf (a self-drop) instead of re-copying it. False for byte-less stores.
    func contains(_ url: URL) -> Bool
    /// Delete the stored bytes for these items. Best-effort — a missing payload is not an error.
    func delete(_ items: [ShelfItem])
}

/// A payload store that does nothing — the default where payloads aren't wired (and for index-only
/// tests). Keeps `ShelfStore` constructible without a filesystem; `store(_:)` is unsupported (a noop
/// store can't hold bytes), so a drop against it stages nothing.
public struct NoopShelfPayloadStore: ShelfPayloadStore {
    public init() {}
    public func store(_ source: ShelfPayloadSource) throws -> StoredPayload {
        throw ShelfPayloadStoreError.unsupported
    }
    public func url(for item: ShelfItem) -> URL? { nil }
    public func contains(_ url: URL) -> Bool { false }
    public func delete(_ items: [ShelfItem]) {}
}
