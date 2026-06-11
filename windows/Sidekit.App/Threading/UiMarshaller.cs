using System.Windows.Forms;

namespace Sidekit.App.Threading;

/// <summary>
/// Marshals work onto the UI thread (the STA, message-pumping thread that owns the tray and forms).
/// Backed by a parentless <see cref="Control"/> whose handle is created on the UI thread, so
/// <see cref="Invoke(System.Action)"/>/<see cref="Post"/> post to that thread's message loop. Used to
/// run clipboard ops (STA-only) and tray/overlay updates from the background dictation cycle. Must be
/// constructed on the UI thread.
/// </summary>
internal sealed class UiMarshaller : IDisposable
{
    private readonly Control _control;

    public UiMarshaller()
    {
        _control = new Control();
        _ = _control.Handle; // force handle creation on the current (UI) thread, so Invoke has a target
    }

    /// <summary>Run <paramref name="func"/> on the UI thread and return its result (blocks the caller).</summary>
    public T Invoke<T>(Func<T> func) =>
        _control.InvokeRequired ? (T)_control.Invoke(func) : func();

    /// <summary>Run a void <paramref name="action"/> on the UI thread (blocks the caller). Needed for the
    /// void clipboard ops (SetText/Clear) — a void lambda can't bind to the <see cref="Invoke{T}"/> overload.</summary>
    public void Invoke(Action action)
    {
        if (_control.InvokeRequired)
        {
            _control.Invoke(action);
        }
        else
        {
            action();
        }
    }

    /// <summary>Queue <paramref name="action"/> to run on the UI thread without blocking the caller.
    /// A no-op once the UI thread has shut down (the app is quitting mid-cycle), so a background
    /// cycle's error report can't throw on a thread-pool thread during teardown.</summary>
    public void Post(Action action)
    {
        try
        {
            _control.BeginInvoke(action);
        }
        catch (Exception) when (_control.IsDisposed)
        {
            // UI thread/handle is gone (quit during an in-flight cycle): drop the marshalled work.
        }
    }

    public void Dispose() => _control.Dispose();
}
