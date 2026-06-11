using System;
using System.IO;
using Sidekit.Core.Logging;

namespace Sidekit.Tests.Logging;

public sealed class FileLogSinkTests : IDisposable
{
    private readonly string _tempDir;

    public FileLogSinkTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "sidekit-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    [Fact]
    public void Write_creates_file_and_missing_directory()
    {
        var path = Path.Combine(_tempDir, "logs", "sidekit.log");
        var sink = new FileLogSink(path);

        sink.Write("recording 7.2s");

        Assert.True(File.Exists(path));
        Assert.Contains("recording 7.2s", File.ReadAllText(path));
    }

    [Fact]
    public void Write_appends_rather_than_overwrites()
    {
        var path = Path.Combine(_tempDir, "sidekit.log");
        var sink = new FileLogSink(path);

        sink.Write("first");
        sink.Write("second");

        var lines = File.ReadAllLines(path);
        Assert.Equal(2, lines.Length);
        Assert.Contains("first", lines[0]);
        Assert.Contains("second", lines[1]);
    }

    [Fact]
    public void Write_prefixes_each_line_with_timestamp()
    {
        var path = Path.Combine(_tempDir, "sidekit.log");
        var now = new DateTimeOffset(2026, 6, 2, 14, 3, 1, TimeSpan.Zero);
        var sink = new FileLogSink(path, () => now);

        sink.Write("latency 1.8s");

        var line = File.ReadAllLines(path)[0];
        Assert.StartsWith("2026-06-02 14:03:01", line);
        Assert.EndsWith("latency 1.8s", line);
    }

    [Fact]
    public void Write_rolls_file_preserving_old_content_in_backup()
    {
        var path = Path.Combine(_tempDir, "sidekit.log");
        var sink = new FileLogSink(path, maxBytes: 10);

        sink.Write("older");  // file empty → no roll; file now exceeds 10 bytes
        sink.Write("newer");  // pre-write size ≥ 10 → roll old content to .1, fresh file gets this

        Assert.Contains("older", File.ReadAllText(path + ".1"));
        var current = File.ReadAllText(path);
        Assert.Contains("newer", current);
        Assert.DoesNotContain("older", current);
    }

    [Fact]
    public void Constructor_rejects_nonpositive_max_bytes()
    {
        var path = Path.Combine(_tempDir, "sidekit.log");
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileLogSink(path, maxBytes: 0));
    }

    [Fact]
    public void Write_is_best_effort_and_swallows_io_failure()
    {
        // Put a FILE where the log's parent directory would need to be, so Directory.CreateDirectory
        // throws — a failed log write must never propagate to (and break) the caller.
        var blocker = Path.Combine(_tempDir, "blocker");
        File.WriteAllText(blocker, "x");
        var sink = new FileLogSink(Path.Combine(blocker, "sidekit.log"));

        Assert.Null(Record.Exception(() => sink.Write("recording 7.2s")));
    }

    [Fact]
    public void Write_collapses_embedded_newlines_into_one_line()
    {
        var path = Path.Combine(_tempDir, "sidekit.log");
        var sink = new FileLogSink(path);

        sink.Write("transcript: line one\nline two\r\nline three");

        var lines = File.ReadAllLines(path);
        Assert.Single(lines);
        Assert.Contains("line one line two line three", lines[0]);
    }
}
