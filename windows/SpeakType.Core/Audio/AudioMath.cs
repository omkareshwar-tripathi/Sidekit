namespace SpeakType.Core.Audio;

/// <summary>
/// Pure, cross-platform audio math used by capture adapters: PCM decoding,
/// linear-interpolation resampling, and an RMS silence gate. No I/O, no
/// platform calls — all behavior is deterministic and unit-testable.
/// </summary>
public static class AudioMath
{
    /// <summary>Sample rate Whisper expects: 16 kHz mono.</summary>
    public const int TargetSampleRate = 16000;

    /// <summary>
    /// Default RMS gate. Tunable: chosen so a near-silent buffer (line/quiet-room
    /// noise) is rejected while a normal speech-level buffer passes. Raise it to
    /// reject quieter speech, lower it to accept fainter input.
    /// </summary>
    public const float DefaultRmsThreshold = 0.01f;

    /// <summary>
    /// Decodes little-endian signed 16-bit PCM to float in [-1, 1] (÷ 32768).
    /// A trailing odd byte (incomplete sample) is ignored.
    /// </summary>
    public static float[] Pcm16ToFloat(ReadOnlySpan<byte> pcm)
    {
        var count = pcm.Length / 2;
        var result = new float[count];
        for (var i = 0; i < count; i++)
        {
            var sample = (short)(pcm[2 * i] | (pcm[2 * i + 1] << 8));
            result[i] = sample / 32768f;
        }

        return result;
    }

    /// <summary>
    /// Linear-interpolation resample of mono samples from
    /// <paramref name="sourceSampleRate"/> to <paramref name="targetSampleRate"/>.
    /// Returns the input array unchanged when the rates match; empty in → empty out.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">Either rate is &lt;= 0.</exception>
    public static float[] Resample(float[] mono, int sourceSampleRate, int targetSampleRate)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sourceSampleRate);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(targetSampleRate);

        if (sourceSampleRate == targetSampleRate || mono.Length == 0)
        {
            // Returns the caller's array by reference (no copy); current callers treat
            // the result as read-only, so the aliasing is safe.
            return mono;
        }

        var targetLength = (int)Math.Round(mono.Length * (double)targetSampleRate / sourceSampleRate);
        if (targetLength <= 1)
        {
            return targetLength == 0 ? Array.Empty<float>() : new[] { mono[0] };
        }

        var result = new float[targetLength];
        var step = (double)(mono.Length - 1) / (targetLength - 1);
        for (var i = 0; i < targetLength; i++)
        {
            var pos = i * step;
            var left = (int)pos;
            var right = Math.Min(left + 1, mono.Length - 1);
            var frac = (float)(pos - left);
            result[i] = mono[left] + (mono[right] - mono[left]) * frac;
        }

        return result;
    }

    /// <summary>
    /// True when the buffer's RMS (root mean square) is at or above
    /// <paramref name="rmsThreshold"/>. An empty buffer is treated as silent.
    /// </summary>
    public static bool HasSpeech(ReadOnlySpan<float> samples, float rmsThreshold)
    {
        if (samples.Length == 0)
        {
            return false;
        }

        double sumOfSquares = 0;
        foreach (var sample in samples)
        {
            sumOfSquares += (double)sample * sample;
        }

        var rms = Math.Sqrt(sumOfSquares / samples.Length);
        return rms >= rmsThreshold;
    }
}
