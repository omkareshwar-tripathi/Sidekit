using System.Net.Http;
using Sidekit.Core.Audio;
using Sidekit.Core.Models;
using Xunit;

namespace Sidekit.Whisper.Tests;

/// <summary>
/// End-to-end integration test: downloads tiny.en via the real model store, decodes a
/// committed WAV, and runs Whisper. Exercises the whole Bricks 5+6+7 chain. Skipped
/// (not failed) when the model cannot be fetched (offline).
/// </summary>
[Trait("Category", "Integration")]
public sealed class WhisperTranscriberTests
{
    [SkippableFact]
    public async Task Transcribes_known_audio_end_to_end()
    {
        var cacheDir = Path.Combine(Path.GetTempPath(), "sidekit-whisper-itest-models");
        string modelPath;
        try
        {
            var store = new ModelStore(new HttpModelDownloader(new HttpClient()), cacheDir);
            modelPath = await store.EnsureAsync("tiny.en", null, CancellationToken.None);
        }
        catch (Exception ex)
        {
            throw new SkipException($"tiny.en unavailable (offline?) — integration test skipped: {ex.Message}");
        }

        var wavBytes = File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "assets", "hello.wav"));
        var pcm = ExtractWavData(wavBytes);
        var samples = AudioMath.Pcm16ToFloat(pcm);

        using var transcriber = new WhisperTranscriber(modelPath);
        var text = transcriber.Transcribe(samples);

        Assert.Contains("quick", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("fox", text, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Scans RIFF chunks for the "data" sub-chunk and returns its bytes.</summary>
    private static byte[] ExtractWavData(byte[] wav)
    {
        var pos = 12; // skip "RIFF" + size + "WAVE"
        while (pos + 8 <= wav.Length)
        {
            var id = System.Text.Encoding.ASCII.GetString(wav, pos, 4);
            var size = BitConverter.ToInt32(wav, pos + 4);
            var dataStart = pos + 8;
            if (id == "data")
            {
                return wav[dataStart..(dataStart + Math.Min(size, wav.Length - dataStart))];
            }

            pos = dataStart + size + (size & 1); // chunks are word-aligned
        }

        throw new InvalidOperationException("No 'data' chunk found in WAV.");
    }
}
