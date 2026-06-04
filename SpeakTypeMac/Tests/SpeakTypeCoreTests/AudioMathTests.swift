import Testing
@testable import SpeakTypeCore

struct AudioMathTests {
    @Test func emptyBufferIsSilent() {
        #expect(!AudioMath.hasSpeech([]))
    }

    @Test func nearSilentBufferIsRejected() {
        let quiet = [Float](repeating: 0.001, count: 1000) // RMS 0.001 < 0.01
        #expect(!AudioMath.hasSpeech(quiet))
    }

    @Test func speechLevelBufferPasses() {
        let loud = [Float](repeating: 0.2, count: 1000) // RMS 0.2 >= 0.01
        #expect(AudioMath.hasSpeech(loud))
    }
}
