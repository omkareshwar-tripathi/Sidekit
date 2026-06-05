namespace SpeakType.Core.Overlay;

/// <summary>The recording overlay's status (spec Feature 6). Listening/Transcribing
/// track the held/released key; NoSpeech and CopiedManually report outcomes after
/// transcription, each mapped to fixed display text by <see cref="OverlayText"/>.</summary>
public enum OverlayStatus { Listening, Transcribing, NoSpeech, CopiedManually }

public static class OverlayText
{
    /// <summary>The exact text shown for each overlay status (spec Feature 6).</summary>
    public static string For(OverlayStatus status) => status switch
    {
        OverlayStatus.Listening => "🎙 Listening…",
        OverlayStatus.Transcribing => "⚙ Transcribing…",
        OverlayStatus.NoSpeech => "No speech detected",
        OverlayStatus.CopiedManually => "Copied — paste manually",
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
    };
}
