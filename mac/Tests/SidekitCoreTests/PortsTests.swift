import Testing
@testable import SidekitCore

// MAC-1 sanity tests: prove the package + test target build and run, and pin the
// shared value types the coordinator (MAC-2) will depend on.

@Test func capturedAudioStoresSamplesAndSpeechFlag() {
    let audio = CapturedAudio(samples: [0.1, -0.2, 0.3], hasSpeech: true)
    #expect(audio.samples == [0.1, -0.2, 0.3])
    #expect(audio.hasSpeech)
}

@Test func capturedAudioEqualityComparesSamplesAndFlag() {
    let a = CapturedAudio(samples: [1], hasSpeech: true)
    let b = CapturedAudio(samples: [1], hasSpeech: true)
    let c = CapturedAudio(samples: [1], hasSpeech: false)
    #expect(a == b)
    #expect(a != c)
}

@Test func pasteOutcomeCasesAreDistinct() {
    #expect(PasteOutcome.pasted != PasteOutcome.leftOnClipboard)
}

@Test func dictationStateHasFourCases() {
    let all: [DictationState] = [.idle, .recording, .transcribing, .pasting]
    #expect(Set(all).count == 4)
}
