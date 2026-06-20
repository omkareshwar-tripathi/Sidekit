using System;
using Sidekit.Core.Time;

namespace Sidekit.Tests.Time;

public sealed class SystemClockTests
{
    [Fact]
    public void GetElapsedTime_of_a_timestamp_one_second_in_the_past_is_about_one_second()
    {
        var clock = new SystemClock();
        var oneSecondAgo = clock.GetTimestamp() - System.Diagnostics.Stopwatch.Frequency;

        var elapsed = clock.GetElapsedTime(oneSecondAgo);

        Assert.True(elapsed >= TimeSpan.FromMilliseconds(900), $"elapsed was {elapsed}");
        Assert.True(elapsed <= TimeSpan.FromMilliseconds(1100), $"elapsed was {elapsed}");
    }

    [Fact]
    public void GetElapsedTime_is_never_negative_for_a_just_taken_timestamp()
    {
        var clock = new SystemClock();

        var t = clock.GetTimestamp();

        Assert.True(clock.GetElapsedTime(t) >= TimeSpan.Zero);
    }

    [Fact]
    public void GetTimestamp_is_monotonic_non_decreasing()
    {
        var clock = new SystemClock();

        var first = clock.GetTimestamp();
        var second = clock.GetTimestamp();

        Assert.True(second >= first);
    }
}
