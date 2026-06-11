import Testing
@testable import SidekitCore

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

    // MARK: - level (0…1 waveform meter)

    @Test func levelOfEmptyBufferIsZero() {
        #expect(AudioMath.level([]) == 0)
    }

    @Test func levelOfReferencePeakIsFull() {
        #expect(AudioMath.level([AudioMath.loudPeak]) == 1)
    }

    @Test func levelIsLinearBelowReference() {
        // Half the reference peak → half deflection.
        #expect(AudioMath.level([AudioMath.loudPeak / 2]) == 0.5)
    }

    @Test func levelClampsAboveReference() {
        #expect(AudioMath.level([1.0]) == 1) // peak far above reference, clamped
    }

    @Test func levelUsesPeakNotAverage() {
        var samples = [Float](repeating: 0.0, count: 1000)
        samples[500] = AudioMath.loudPeak // a single loud sample drives the meter
        #expect(AudioMath.level(samples) == 1)
    }
}
