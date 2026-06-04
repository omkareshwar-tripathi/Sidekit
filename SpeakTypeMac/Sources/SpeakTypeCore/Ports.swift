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
/// comes back up.
public protocol HotkeyListening: AnyObject {
    var onPressed: (() -> Void)? { get set }
    var onReleased: (() -> Void)? { get set }
}

/// Inserts text into the focused application, or leaves it on the clipboard.
public protocol Pasting: AnyObject {
    func paste(_ text: String) -> PasteOutcome
}

/// Turns 16 kHz mono samples into a transcript. Async because WhisperKit is async.
public protocol Transcribing: AnyObject {
    func transcribe(_ samples: [Float]) async -> String
}
