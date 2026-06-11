namespace Sidekit.Core.Audio;

/// <summary>
/// Microphone capture port. <see cref="Start"/> begins recording;
/// <see cref="Stop"/> ends it and returns the captured buffer.
/// </summary>
public interface IAudioCapture
{
    void Start();
    CapturedAudio Stop();
}

/// <summary>Captured 16 kHz mono audio. <paramref name="HasSpeech"/> is the
/// adapter's silence-gate (RMS) verdict; false means near-silent.</summary>
public sealed record CapturedAudio(float[] Samples, bool HasSpeech);
