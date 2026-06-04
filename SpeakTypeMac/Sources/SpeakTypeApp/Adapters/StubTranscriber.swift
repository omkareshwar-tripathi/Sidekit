import SpeakTypeCore

/// Temporary transcriber used to verify the mic → Fn → paste pipeline before WhisperKit is
/// wired in (brick MAC-6). Pastes a marker that includes the captured sample count, so a real
/// hold-and-speak proves audio was actually captured end-to-end. Replaced by
/// `WhisperKitTranscriber` in MAC-6.
struct StubTranscriber: Transcribing {
    func transcribe(_ samples: [Float]) async -> String {
        "speaktype works — captured \(samples.count) samples"
    }
}
