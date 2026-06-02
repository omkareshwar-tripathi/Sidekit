using SpeakType.Core.Audio;

namespace SpeakType.Tests.Audio;

public sealed class AudioMathTests
{
    [Fact]
    public void Pcm16ToFloat_converts_known_byte_pairs()
    {
        // 0x00 0x80 = -32768 → -1.0; 0xFF 0x7F = 32767 → ~0.99997; 0x00 0x00 = 0.
        byte[] pcm = { 0x00, 0x80, 0xFF, 0x7F, 0x00, 0x00 };

        var result = AudioMath.Pcm16ToFloat(pcm);

        Assert.Equal(3, result.Length);
        Assert.Equal(-1.0, result[0], 5);
        Assert.Equal(32767.0 / 32768.0, result[1], 5);
        Assert.Equal(0.0, result[2], 5);
    }

    [Fact]
    public void Pcm16ToFloat_ignores_trailing_odd_byte()
    {
        byte[] pcm = { 0x00, 0x00, 0x42 };

        var result = AudioMath.Pcm16ToFloat(pcm);

        Assert.Single(result);
        Assert.Equal(0f, result[0]);
    }

    [Fact]
    public void HasSpeech_returns_false_for_all_zero_buffer()
    {
        var samples = new float[1000];

        Assert.False(AudioMath.HasSpeech(samples, AudioMath.DefaultRmsThreshold));
    }

    [Fact]
    public void HasSpeech_returns_false_for_empty_buffer()
    {
        Assert.False(AudioMath.HasSpeech(Array.Empty<float>(), AudioMath.DefaultRmsThreshold));
    }

    [Fact]
    public void HasSpeech_returns_true_for_speech_level_sine()
    {
        // Amplitude 0.2 sine → RMS ≈ 0.2/sqrt(2) ≈ 0.14, well above the default threshold.
        var samples = Sine(frequency: 440, sampleRate: 16000, count: 1600, amplitude: 0.2f);

        Assert.True(AudioMath.HasSpeech(samples, AudioMath.DefaultRmsThreshold));
    }

    [Fact]
    public void Resample_same_rate_returns_unchanged_length()
    {
        var samples = Sine(frequency: 200, sampleRate: 16000, count: 800, amplitude: 0.5f);

        var result = AudioMath.Resample(samples, 16000, 16000);

        Assert.Equal(samples.Length, result.Length);
        Assert.Same(samples, result);
    }

    [Fact]
    public void Resample_empty_input_yields_empty_output()
    {
        var result = AudioMath.Resample(Array.Empty<float>(), 32000, 16000);

        Assert.Empty(result);
    }

    [Fact]
    public void Resample_downsampling_halves_length()
    {
        var samples = new float[1000];

        var result = AudioMath.Resample(samples, 32000, 16000);

        Assert.InRange(result.Length, 499, 501);
    }

    [Fact]
    public void Resample_upsampling_roughly_doubles_length()
    {
        var samples = Sine(frequency: 100, sampleRate: 8000, count: 400, amplitude: 0.5f);

        var result = AudioMath.Resample(samples, 8000, 16000);

        Assert.InRange(result.Length, 799, 801);
    }

    [Fact]
    public void Resample_preserves_constant_signal()
    {
        var samples = new float[500];
        Array.Fill(samples, 0.33f);

        var result = AudioMath.Resample(samples, 16000, 8000);

        Assert.All(result, v => Assert.Equal(0.33, v, 4));
    }

    [Fact]
    public void Resample_preserves_endpoints_of_known_sine()
    {
        var samples = Sine(frequency: 50, sampleRate: 8000, count: 400, amplitude: 0.5f);

        var result = AudioMath.Resample(samples, 8000, 16000);

        Assert.Equal((double)samples[0], result[0], 3);
        Assert.Equal((double)samples[^1], result[^1], 3);
    }

    [Theory]
    [InlineData(0, 16000)]
    [InlineData(16000, 0)]
    [InlineData(-1, 16000)]
    public void Resample_throws_on_non_positive_rate(int source, int target)
    {
        Assert.Throws<ArgumentOutOfRangeException>(
            () => AudioMath.Resample(new float[10], source, target));
    }

    private static float[] Sine(int frequency, int sampleRate, int count, float amplitude)
    {
        var samples = new float[count];
        for (var i = 0; i < count; i++)
        {
            samples[i] = amplitude * MathF.Sin(2 * MathF.PI * frequency * i / sampleRate);
        }

        return samples;
    }
}
