import Testing
@testable import SpeakTypeCore

struct AudioMathTests {
    @Test func emptyBufferIsSilent() {
        #expect(!AudioMath.hasSpeech([]))
    }

    @Test func nearSilentBufferIsRejected() {
        let quiet = [Float](repeating: 0.001, count: 1000) // peak 0.001 < 0.02
        #expect(!AudioMath.hasSpeech(quiet))
    }

    @Test func speechLevelBufferPasses() {
        let loud = [Float](repeating: 0.2, count: 1000) // peak 0.2 ≥ 0.02
        #expect(AudioMath.hasSpeech(loud))
    }

    // The real-world case the peak gate fixes: a long push-to-talk buffer that is mostly
    // quiet (silence before/after speech) but contains real speech peaks. RMS would average
    // below threshold and wrongly reject it; peak passes it.
    @Test func mostlyQuietBufferWithSpeechPeaksPasses() {
        var samples = [Float](repeating: 0.0005, count: 60_000) // ~3.75 s of near-silence
        for i in 0..<2000 { samples[10_000 + i] = 0.08 }        // a short burst of speech
        #expect(AudioMath.hasSpeech(samples))
    }
}
