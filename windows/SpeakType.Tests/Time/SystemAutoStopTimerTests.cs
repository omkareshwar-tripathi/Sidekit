using System;
using System.Threading;
using SpeakType.Core.Time;

namespace SpeakType.Tests.Time;

public sealed class SystemAutoStopTimerTests
{
    [Fact]
    public void Start_fires_callback_after_the_delay()
    {
        using var timer = new SystemAutoStopTimer();
        using var fired = new ManualResetEventSlim();

        timer.Start(TimeSpan.FromMilliseconds(50), fired.Set);

        Assert.True(fired.Wait(TimeSpan.FromSeconds(2)));
    }

    [Fact]
    public void Cancel_before_delay_prevents_the_callback()
    {
        using var timer = new SystemAutoStopTimer();
        var count = 0;

        timer.Start(TimeSpan.FromMilliseconds(150), () => Interlocked.Increment(ref count));
        timer.Cancel();
        Thread.Sleep(400);

        Assert.Equal(0, Volatile.Read(ref count));
    }

    [Fact]
    public void Timer_fires_only_once()
    {
        using var timer = new SystemAutoStopTimer();
        using var fired = new ManualResetEventSlim();
        var count = 0;

        timer.Start(TimeSpan.FromMilliseconds(50), () =>
        {
            Interlocked.Increment(ref count);
            fired.Set();
        });

        Assert.True(fired.Wait(TimeSpan.FromSeconds(2)));
        Thread.Sleep(200);
        Assert.Equal(1, Volatile.Read(ref count));
    }

    [Fact]
    public void Cancel_when_not_running_is_a_no_op()
    {
        Assert.Null(Record.Exception(() => new SystemAutoStopTimer().Cancel()));
    }

    [Fact]
    public void Start_throws_when_callback_is_null()
    {
        using var timer = new SystemAutoStopTimer();

        Assert.Throws<ArgumentNullException>(() => timer.Start(TimeSpan.FromMilliseconds(10), null!));
    }
}
