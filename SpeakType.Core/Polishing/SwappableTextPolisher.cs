namespace SpeakType.Core.Polishing;

/// <summary>
/// An <see cref="ITextPolisher"/> whose inner polisher can be set (or cleared) at runtime, so the
/// composition root can switch CoEdIT on after the user enables it and its model has downloaded —
/// without rebuilding the orchestrator.
/// <para>
/// When no inner is set it is a pass-through: <see cref="Polish"/> returns the text unchanged. This
/// is the "CoEdIT off / not yet downloaded" state, and keeps the consumer fail-open by construction.
/// </para>
/// <para>
/// Threading mirrors <c>SwappableTranscriber</c>: <see cref="Polish"/> (called on the background
/// dictation cycle) and <see cref="Set"/> (called on the UI thread) are serialized by a lock, so a
/// swap never tears an in-flight polish; the replaced inner is disposed outside the lock. <see cref="Set"/>
/// and <see cref="Dispose"/> must not race each other (one user action at a time, by design).
/// </para>
/// </summary>
public sealed class SwappableTextPolisher : ITextPolisher, IDisposable
{
    private readonly object _gate = new();
    private ITextPolisher? _inner;

    /// <summary>True when a real polisher is set (CoEdIT active); false when pass-through.</summary>
    public bool IsActive
    {
        get { lock (_gate) { return _inner is not null; } }
    }

    public string Polish(string text)
    {
        lock (_gate)
        {
            return _inner is null ? text : _inner.Polish(text);
        }
    }

    /// <summary>
    /// Sets the active inner polisher (or clears it with <c>null</c>, returning to pass-through),
    /// disposing the one it replaced. A no-op (no dispose) if <paramref name="newInner"/> is already
    /// the current inner.
    /// </summary>
    public void Set(ITextPolisher? newInner)
    {
        ITextPolisher? old;
        lock (_gate)
        {
            if (ReferenceEquals(newInner, _inner))
            {
                return;
            }

            old = _inner;
            _inner = newInner;
        }

        (old as IDisposable)?.Dispose(); // safe outside the lock: no Polish call can still be using old
    }

    public void Dispose()
    {
        ITextPolisher? inner;
        lock (_gate)
        {
            inner = _inner;
        }

        (inner as IDisposable)?.Dispose();
    }
}
