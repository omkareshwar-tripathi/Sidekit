namespace SpeakType.Core.Paste;

/// <summary>
/// Clipboard-safe paste (spec Feature 5). The sequence: save the current clipboard text,
/// set our text (so the user's words are never silently lost), then check for a focused
/// editable target. If one is confirmed it simulates Ctrl+V, waits briefly so the target
/// app can read the clipboard, then restores the original text. If no target is confirmed
/// it leaves our text on the clipboard for a manual paste and restores nothing.
/// </summary>
public sealed class ClipboardPasteService : IPasteService
{
    // Tunable wait from spec Feature 5 step 4 — gives the target app time to read the
    // clipboard after Ctrl+V before we restore the original text.
    private static readonly TimeSpan RestoreDelay = TimeSpan.FromMilliseconds(150);

    private readonly IClipboard _clipboard;
    private readonly Action<TimeSpan> _sleep;

    public ClipboardPasteService(IClipboard clipboard, Action<TimeSpan>? sleep = null)
    {
        ArgumentNullException.ThrowIfNull(clipboard);
        _clipboard = clipboard;
        _sleep = sleep ?? Thread.Sleep;
    }

    public PasteOutcome Paste(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var original = _clipboard.GetText(); // save first
        _clipboard.SetText(text);            // set our text (kept on clipboard in both branches)

        if (!_clipboard.HasEditableTarget())
        {
            return PasteOutcome.LeftOnClipboard; // no confirmed target → leave it for manual paste
        }

        if (!_clipboard.SendPaste())
        {
            // The OS blocked the paste keystrokes (e.g. an elevated foreground window).
            // Leave our text on the clipboard rather than restoring over it — never
            // silently lose the user's words.
            return PasteOutcome.LeftOnClipboard;
        }

        _sleep(RestoreDelay);

        if (original is null)
        {
            _clipboard.Clear();
        }
        else
        {
            _clipboard.SetText(original);
        }

        return PasteOutcome.Pasted;
    }
}
