using System;
using System.Collections.Generic;
using Sidekit.Core.Logging;

namespace Sidekit.Tests.Logging;

public sealed class AppLoggerTests
{
    private sealed class FakeSink : ILogSink
    {
        public List<string> Lines { get; } = new();
        public void Write(string message) => Lines.Add(message);
    }

    [Fact]
    public void Recording_writes_duration_in_seconds()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => false);

        logger.Recording(TimeSpan.FromSeconds(7.2));

        Assert.Equal("recording 7.2s", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Transcribed_writes_duration_and_char_count()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => false);

        logger.Transcribed(TimeSpan.FromSeconds(1.4), 38);

        Assert.Equal("transcribe 1.4s, 38 chars", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Latency_writes_release_to_paste_seconds()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => false);

        logger.Latency(TimeSpan.FromSeconds(1.8));

        Assert.Equal("latency 1.8s", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Error_writes_prefixed_message()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => false);

        logger.Error("disk full");

        Assert.Equal("error: disk full", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Transcript_writes_nothing_when_debug_disabled()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => false);

        logger.Transcript("secret words");

        Assert.Empty(fake.Lines);
        Assert.DoesNotContain(fake.Lines, line => line.Contains("secret"));
    }

    [Fact]
    public void Transcript_writes_text_when_debug_enabled()
    {
        var fake = new FakeSink();
        var logger = new AppLogger(fake, () => true);

        logger.Transcript("secret words");

        Assert.Equal("transcript: secret words", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Transcript_reads_debug_flag_live_on_each_call()
    {
        var fake = new FakeSink();
        var enabled = false;
        var logger = new AppLogger(fake, () => enabled);

        logger.Transcript("first");
        Assert.Empty(fake.Lines); // flag still off — nothing written yet (proves it isn't cached on at construction)
        enabled = true;
        logger.Transcript("second");

        Assert.Equal("transcript: second", Assert.Single(fake.Lines));
    }

    [Fact]
    public void Constructor_throws_when_sink_is_null()
    {
        Assert.Throws<ArgumentNullException>(() => new AppLogger(null!, () => false));
    }

    [Fact]
    public void Constructor_throws_when_debugEnabled_is_null()
    {
        Assert.Throws<ArgumentNullException>(() => new AppLogger(new FakeSink(), null!));
    }
}
