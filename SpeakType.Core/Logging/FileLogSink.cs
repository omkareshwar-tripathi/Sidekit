using System.Globalization;

namespace SpeakType.Core.Logging;

/// <summary>
/// Rolling local log file: a size-based roll keeps exactly one backup
/// (<c>speaktype.log.1</c>), bounding disk use to roughly twice the limit.
/// Timestamps and thread-safe appends live here; message formatting lives in
/// <see cref="AppLogger"/>. Writes are serialized so the timer, UI, and
/// background threads cannot interleave or corrupt a line.
/// </summary>
public sealed class FileLogSink : ILogSink
{
    private readonly string _filePath;
    private readonly Func<DateTimeOffset> _now;
    private readonly long _maxBytes;
    private readonly object _gate = new();

    public FileLogSink(string filePath, Func<DateTimeOffset>? now = null, long maxBytes = 5_000_000)
    {
        ArgumentException.ThrowIfNullOrEmpty(filePath);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxBytes); // a non-positive cap rolls every write, destroying history
        _filePath = filePath;
        _now = now ?? (() => DateTimeOffset.Now);
        _maxBytes = maxBytes;
    }

    public static string DefaultLogPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        AppInfo.Name,
        "logs",
        "speaktype.log");

    public void Write(string message)
    {
        lock (_gate)
        {
            try
            {
                // One physical line per event: collapse any embedded newlines so a multi-line
                // transcript can't break the line-per-event format or forge a timestamped line.
                var sanitized = message.ReplaceLineEndings(" ");

                var directory = Path.GetDirectoryName(_filePath);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                if (File.Exists(_filePath) && new FileInfo(_filePath).Length >= _maxBytes)
                {
                    File.Move(_filePath, _filePath + ".1", overwrite: true);
                }

                var line = $"{_now().ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture)} {sanitized}";
                File.AppendAllText(_filePath, line + Environment.NewLine);
            }
            catch (Exception)
            {
                // Best-effort logging: a diagnostic log must never take down the app it observes
                // (disk full, permissions, an AV lock, a deleted dir mid-run). Swallow and move on.
            }
        }
    }
}
