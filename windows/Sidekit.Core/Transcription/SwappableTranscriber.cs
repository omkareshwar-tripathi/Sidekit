namespace Sidekit.Core.Transcription;

/// <summary>
/// An <see cref="ITranscriber"/> that delegates to a current inner transcriber which can be
/// hot-swapped at runtime (model switch, spec Feature 4) without rebuilding the consumer.
/// <para>
/// <see cref="Transcribe"/> and <see cref="Swap"/> are serialized by a lock so a swap can never
/// tear an in-flight transcription: <see cref="Transcribe"/> holds the lock for its whole call, so
/// once <see cref="Swap"/> has taken the lock no transcription is running against the old inner.
/// <see cref="Swap"/> therefore disposes the replaced inner safely, doing so outside the lock to
/// avoid holding it across a potentially slow native dispose. This type OWNS its current inner:
/// <see cref="Dispose"/> disposes it. A <see cref="Swap"/> may block until an in-flight
/// <see cref="Transcribe"/> completes, but that is rare in practice (the user is not dictating while
/// changing the model).
/// </para>
/// <para>
/// Threading contract: <see cref="Transcribe"/> may run on a different thread (the background
/// dictation cycle) concurrently with <see cref="Swap"/> or <see cref="Dispose"/> — the lock makes
/// that safe. <see cref="Swap"/> and <see cref="Dispose"/> must NOT race each other or a second
/// <see cref="Swap"/>; call them from a single thread (in this app, the UI thread). A model switch
/// is one user action, so concurrent swaps are out of scope by design. Do not call after
/// <see cref="Dispose"/>. Thread-safety here is argued, not stress-tested (same precedent as
/// <c>SystemAutoStopTimer</c> and <c>FileLogSink</c>).
/// </para>
/// </summary>
public sealed class SwappableTranscriber : ITranscriber, IDisposable
{
    private readonly object _gate = new();
    private ITranscriber _inner;

    public SwappableTranscriber(ITranscriber inner)
    {
        ArgumentNullException.ThrowIfNull(inner);
        _inner = inner;
    }

    public string Transcribe(float[] samples)
    {
        lock (_gate)
        {
            return _inner.Transcribe(samples);
        }
    }

    /// <summary>
    /// Replaces the current inner transcriber and disposes the one it replaced. A no-op (and no
    /// dispose) if <paramref name="newInner"/> is already the current inner.
    /// </summary>
    public void Swap(ITranscriber newInner)
    {
        ArgumentNullException.ThrowIfNull(newInner);
        ITranscriber old;
        lock (_gate)
        {
            if (ReferenceEquals(newInner, _inner))
            {
                return;
            }

            old = _inner;
            _inner = newInner;
        }

        (old as IDisposable)?.Dispose(); // safe outside the lock: no call can still be using old
    }

    public void Dispose()
    {
        ITranscriber inner;
        lock (_gate)
        {
            inner = _inner;
        }

        (inner as IDisposable)?.Dispose();
    }
}
