using System.Globalization;

namespace Sidekit.Core.Logging;

/// <summary>
/// Formats one log line per event and writes it to an <see cref="ILogSink"/>.
/// Metadata events (recording, transcribe, latency, error) are always emitted;
/// the transcribed text is emitted only when debug logging is enabled — by
/// default a transcript is never written to disk (spec: Logging &amp; Privacy).
/// Formatting lives here so it is unit-testable in isolation; the sink owns
/// timestamping and persistence. All numbers use
/// <see cref="CultureInfo.InvariantCulture"/> so locale never changes the output.
/// </summary>
public sealed class AppLogger
{
    private readonly ILogSink _sink;
    private readonly Func<bool> _debugEnabled;

    public AppLogger(ILogSink sink, Func<bool> debugEnabled)
    {
        ArgumentNullException.ThrowIfNull(sink);
        ArgumentNullException.ThrowIfNull(debugEnabled);
        _sink = sink;
        _debugEnabled = debugEnabled;
    }

    public void Recording(TimeSpan duration) =>
        _sink.Write($"recording {Seconds(duration)}s");

    public void Transcribed(TimeSpan duration, int charCount) =>
        _sink.Write($"transcribe {Seconds(duration)}s, {charCount} chars");

    public void Latency(TimeSpan releaseToPaste) =>
        _sink.Write($"latency {Seconds(releaseToPaste)}s");

    /// <summary>
    /// Records the transcribed text, but only when debug logging is enabled
    /// (read live, so toggling the setting applies immediately). In the default
    /// mode this writes nothing, keeping transcripts off disk.
    /// </summary>
    public void Transcript(string text)
    {
        if (_debugEnabled())
        {
            _sink.Write($"transcript: {text}");
        }
    }

    public void Error(string message) =>
        _sink.Write($"error: {message}");

    private static string Seconds(TimeSpan span) =>
        span.TotalSeconds.ToString("0.0", CultureInfo.InvariantCulture);
}
