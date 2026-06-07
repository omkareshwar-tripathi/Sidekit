namespace SpeakType.Core.Paste;

/// <summary>
/// Clipboard-safe paste (spec Feature 5). The sequence: save the current clipboard text,
/// set our text (so the user's words are never silently lost), then simulate Ctrl+V into
/// whatever app is focused. If the keystroke is injected it waits briefly so the target app
/// can read the clipboard, then restores the original text. If the OS blocks the keystroke
/// (e.g. an elevated foreground window) it leaves our text on the clipboard for a manual
/// paste and restores nothing. We always attempt the paste rather than pre-checking for an
/// editable target: focus detection is unreliable across modern apps (browsers, Electron,
/// WinUI), so a confirm-first check produced far more false "no target" misses than the
/// harmless stray Ctrl+V it avoided.
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
