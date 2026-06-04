/// Pure audio math for capture adapters — the speech-presence gate.
///
/// Uses PEAK amplitude, not RMS. Push-to-talk buffers include the quiet moments before and
/// after you actually speak, so RMS averaged over the whole buffer badly underestimates
/// speech presence: on a real Mac mic, clear speech peaked at ~0.08 while the buffer's RMS
/// fell below an 0.01 RMS gate → speech was wrongly rejected. Peak is independent of how
/// much silence padding the buffer holds: quiet-room noise stays well under the threshold,
/// while any real speech clears it.
public enum AudioMath {
    /// Default peak gate. Room/line noise peaks well below this; normal speech peaks far above.
    public static let speechPeakThreshold: Float = 0.02

    /// True when the buffer's peak amplitude reaches `threshold`. Empty → silent (false).
    public static func hasSpeech(_ samples: [Float], threshold: Float = speechPeakThreshold) -> Bool {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        return peak >= threshold
    }

    /// Peak treated as "full deflection" on the 0…1 meter. Normal speech peaks well below 1.0,
    /// so the live waveform would barely move against a 1.0 reference; this maps a realistic
    /// loud peak to a full bar.
    public static let loudPeak: Float = 0.3

    /// A 0…1 amplitude level for the live recording waveform: the buffer's peak normalized
    /// against `reference` and clamped to 1. Empty → 0. Shares the peak basis with `hasSpeech`.
    public static func level(_ samples: [Float], reference: Float = loudPeak) -> Float {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        return min(1, peak / reference)
    }
}
