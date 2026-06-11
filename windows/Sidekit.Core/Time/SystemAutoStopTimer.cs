namespace Sidekit.Core.Time;

/// <summary>
/// Real <see cref="IAutoStopTimer"/> backed by a single <see cref="System.Threading.Timer"/>.
/// A generation counter guarded by a lock makes one-shot and cancel reliable even against the
/// timer-pool race where a callback is already queued when <see cref="Cancel"/> runs: every
/// state change bumps the generation, and a fired callback only invokes <c>onElapsed</c> if the
/// generation it was scheduled under is still current. User work runs outside the lock.
/// <para>
/// The guard covers a callback still queued or not yet past its generation check; a callback that
/// has <i>already</i> passed the check (now running <c>onElapsed</c> outside the lock) may still
/// complete after <see cref="Cancel"/>/<see cref="Dispose"/> returns. A consumer needing a hard
/// "never fires after cancel" guarantee must also guard on its own side (the orchestrator does,
/// via its recording-state check in <c>OnAutoStop</c>).
/// </para>
/// </summary>
public sealed class SystemAutoStopTimer : IAutoStopTimer, IDisposable
{
    private readonly object _gate = new();
    private Timer? _timer;
    private long _generation;

    public void Start(TimeSpan delay, Action onElapsed)
    {
        ArgumentNullException.ThrowIfNull(onElapsed);
        lock (_gate)
        {
            _generation++;
            var generation = _generation;
            _timer?.Dispose();
            _timer = new Timer(_ => Fire(generation, onElapsed), null, delay, Timeout.InfiniteTimeSpan);
        }
    }

    public void Cancel()
    {
        lock (_gate)
        {
            ClearLocked();
        }
    }

    // Disposal and cancellation do the same thing: bump the generation (invalidating any
    // in-flight or queued callback) and tear down the timer.
    public void Dispose() => Cancel();

    private void Fire(long generation, Action onElapsed)
    {
        lock (_gate)
        {
            if (generation != _generation)
            {
                return; // superseded by a newer Start/Cancel/Dispose
            }

            ClearLocked(); // one-shot: bump past this generation so a duplicate callback can't fire
        }

        onElapsed(); // run user work outside the lock
    }

    // Invalidates any pending callback and tears down the timer. Caller must hold _gate.
    private void ClearLocked()
    {
        _generation++;
        _timer?.Dispose();
        _timer = null;
    }
}
