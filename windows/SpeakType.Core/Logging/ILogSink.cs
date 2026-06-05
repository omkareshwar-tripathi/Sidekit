namespace SpeakType.Core.Logging;

/// <summary>Destination for already-formatted log lines (the rolling file in production,
/// a fake in tests). The sink owns timestamping, persistence, and thread-safety. Writes are
/// best-effort: <see cref="Write"/> must never throw (a failed log must not break the caller)
/// and must emit each message as a single physical line.</summary>
public interface ILogSink
{
    void Write(string message);
}
