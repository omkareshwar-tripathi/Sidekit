namespace Sidekit.Core.Paste;

/// <summary>Inserts text into the focused application, or leaves it on the clipboard.</summary>
public interface IPasteService
{
    PasteOutcome Paste(string text);
}

/// <summary>Result of a paste attempt. <see cref="LeftOnClipboard"/> means no
/// editable target was confirmed, so the text was left on the clipboard for the
/// user to paste manually.</summary>
public enum PasteOutcome { Pasted, LeftOnClipboard }
