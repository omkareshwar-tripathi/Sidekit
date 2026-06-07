using System.Text;
using SpeakType.Core.Transcription;
using Whisper.net;

namespace SpeakType.Whisper;

/// <summary>
/// Whisper.NET-backed <see cref="ITranscriber"/>. The ggml model is loaded once in
/// the constructor and the resulting processor is reused across every
/// <see cref="Transcribe"/> call, so model-load cost is paid once per app session.
/// The orchestrator calls <see cref="Transcribe"/> synchronously; running it on a
/// background thread (and the threading model around it) is Brick 14's concern.
/// </summary>
public sealed class WhisperTranscriber : ITranscriber, IDisposable
{
    private readonly WhisperFactory _factory;
    private readonly WhisperProcessor _processor;
    private bool _disposed;

    /// <summary>
    /// Loads the ggml model at <paramref name="modelPath"/> and builds an
    /// English, multi-threaded processor reused for the lifetime of this instance.
    /// </summary>
    /// <exception cref="ArgumentException"><paramref name="modelPath"/> is null or whitespace.</exception>
    /// <exception cref="FileNotFoundException">No file exists at <paramref name="modelPath"/>.</exception>
    public WhisperTranscriber(string modelPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelPath);
        if (!File.Exists(modelPath))
        {
            throw new FileNotFoundException("Whisper model file not found.", modelPath);
        }

        _factory = WhisperFactory.FromPath(modelPath);
        _processor = _factory.CreateBuilder()
            .WithLanguage("en")
            .WithThreads(Math.Max(1, Environment.ProcessorCount - 1))
            .Build();
    }

    /// <summary>
    /// Transcribes 16 kHz mono <paramref name="samples"/> to text, returning the
    /// trimmed concatenation of all segments. An empty buffer yields <c>""</c>.
    /// </summary>
    /// <exception cref="ArgumentNullException"><paramref name="samples"/> is null.</exception>
    public string Transcribe(float[] samples)
    {
        ArgumentNullException.ThrowIfNull(samples);
        if (samples.Length == 0)
        {
            return "";
        }

        var sb = new StringBuilder();
        foreach (var segment in _processor.ProcessAsync(samples).ToBlockingEnumerable())
        {
            sb.Append(segment.Text);
        }

        return sb.ToString().Trim();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _processor.Dispose();
        _factory.Dispose();
        GC.SuppressFinalize(this);
    }
}
