namespace Sidekit.Core.Time;

/// <summary>
/// Monotonic clock for measuring elapsed time (mirrors <see cref="System.Diagnostics.Stopwatch"/>).
/// Injected so tests can control the press→release duration the hold guards depend on.
/// </summary>
public interface IClock
{
    /// <summary>A monotonic timestamp; only meaningful when passed to <see cref="GetElapsedTime"/>.</summary>
    long GetTimestamp();

    /// <summary>Elapsed time since <paramref name="startingTimestamp"/> (from <see cref="GetTimestamp"/>).</summary>
    TimeSpan GetElapsedTime(long startingTimestamp);
}
