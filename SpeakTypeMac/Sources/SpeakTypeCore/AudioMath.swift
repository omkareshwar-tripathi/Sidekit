/// Pure audio math for capture adapters — the RMS silence gate (a port of the C#
/// `AudioMath.HasSpeech`). Resampling is left to the platform's `AVAudioConverter`, so
/// only the gate is needed here, and it stays deterministic and unit-testable.
public enum AudioMath {
    /// Default RMS gate: a near-silent buffer (quiet room) is rejected, normal speech
    /// passes. Matches the C# `DefaultRmsThreshold`.
    public static let defaultRmsThreshold: Float = 0.01

    /// True when the buffer's RMS is at or above `threshold`. Empty → silent (false).
    public static func hasSpeech(_ samples: [Float], threshold: Float = defaultRmsThreshold) -> Bool {
        guard !samples.isEmpty else { return false }
        var sumOfSquares = 0.0
        for s in samples { sumOfSquares += Double(s) * Double(s) }
        let rms = (sumOfSquares / Double(samples.count)).squareRoot()
        return rms >= Double(threshold)
    }
}
