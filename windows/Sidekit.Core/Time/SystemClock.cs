using System.Diagnostics;

namespace Sidekit.Core.Time;

/// <summary>
/// Real <see cref="IClock"/> backed by <see cref="Stopwatch"/>: a high-resolution
/// monotonic source unaffected by wall-clock changes, used to measure press→release durations.
/// </summary>
public sealed class SystemClock : IClock
{
    public long GetTimestamp() => Stopwatch.GetTimestamp();

    public TimeSpan GetElapsedTime(long startingTimestamp) => Stopwatch.GetElapsedTime(startingTimestamp);
}
