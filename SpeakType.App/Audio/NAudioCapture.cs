using NAudio.Wave;
using SpeakType.Core.Audio;

namespace SpeakType.App.Audio;

/// <summary>
/// Windows <see cref="IAudioCapture"/> backed by NAudio's <see cref="WaveInEvent"/>.
/// Captures mono 16-bit PCM at the device's native rate, then converts/resamples to
/// 16 kHz mono float on <see cref="Stop"/>. The orchestrator (Brick 14) guarantees a
/// single active capture cycle, so Start/Stop are never overlapped.
/// </summary>
public sealed class NAudioCapture : IAudioCapture, IDisposable
{
    private const int NativeSampleRate = 44100;
    private const int Bits = 16;
    private const int Channels = 1;
    private const int DeviceNumber = 0;

    // Guards _buffer: DataAvailable fires on an NAudio background thread.
    private readonly object _lock = new();

    // Pre-size to ~1 s of 44.1 kHz 16-bit mono so a typical recording doesn't
    // repeatedly reallocate the backing array as chunks arrive.
    private readonly List<byte> _buffer = new(NativeSampleRate * (Bits / 8));

    private WaveInEvent? _waveIn;
    private bool _disposed;

    public void Start()
    {
        if (_waveIn != null)
        {
            // Programmer error: the orchestrator's single-active-cycle invariant
            // means Start is never called twice without an intervening Stop.
            return;
        }

        if (WaveInEvent.DeviceCount == 0)
        {
            // The orchestrator's press-path try/catch resets state; the user-facing
            // balloon notification is Brick 9's responsibility.
            throw new InvalidOperationException("No microphone detected.");
        }

        lock (_lock)
        {
            _buffer.Clear();
        }

        _waveIn = new WaveInEvent
        {
            DeviceNumber = DeviceNumber,
            WaveFormat = new WaveFormat(NativeSampleRate, Bits, Channels),
        };
        _waveIn.DataAvailable += OnDataAvailable;
        _waveIn.StartRecording();
    }

    public CapturedAudio Stop()
    {
        var waveIn = _waveIn;
        if (waveIn == null)
        {
            return new CapturedAudio(Array.Empty<float>(), false);
        }

        // Returning the accumulated buffer synchronously after StopRecording is
        // acceptable for v1: a final in-flight partial buffer may be dropped. The
        // precise flush/threading is Brick 14's job.
        waveIn.StopRecording();
        waveIn.DataAvailable -= OnDataAvailable;
        waveIn.Dispose();
        _waveIn = null;

        byte[] pcm;
        lock (_lock)
        {
            pcm = _buffer.ToArray();
            _buffer.Clear();
        }

        var samples = AudioMath.Pcm16ToFloat(pcm);
        var resampled = AudioMath.Resample(samples, NativeSampleRate, AudioMath.TargetSampleRate);
        var hasSpeech = AudioMath.HasSpeech(resampled, AudioMath.DefaultRmsThreshold);
        return new CapturedAudio(resampled, hasSpeech);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        if (_waveIn != null)
        {
            _waveIn.DataAvailable -= OnDataAvailable;
            _waveIn.StopRecording();
            _waveIn.Dispose();
            _waveIn = null;
        }

        GC.SuppressFinalize(this);
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_lock)
        {
            _buffer.AddRange(e.Buffer.AsSpan(0, e.BytesRecorded));
        }
    }
}
