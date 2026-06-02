namespace SpeakType.Core.Time;

/// <summary>
/// One-shot timer for the auto-stop guard: started when recording begins, cancelled on
/// release. If it elapses first, its callback ends the recording the same as a release.
/// </summary>
public interface IAutoStopTimer
{
    /// <summary>Start (or restart) the timer; <paramref name="onElapsed"/> runs once after <paramref name="delay"/>.</summary>
    void Start(TimeSpan delay, Action onElapsed);

    /// <summary>Cancel a started timer so its callback will not run. No-op if not running.</summary>
    void Cancel();
}
