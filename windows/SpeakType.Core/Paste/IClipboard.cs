namespace SpeakType.Core.Paste;

/// <summary>
/// System clipboard and paste primitives the clipboard-safe paste flow depends on.
/// Text-only: the original-content save/restore handles text and treats anything else
/// (or an empty clipboard) as "no text" so it can be restored by clearing.
/// </summary>
public interface IClipboard
{
    /// <summary>The current clipboard text, or <c>null</c> if the clipboard holds no text.</summary>
    string? GetText();

    /// <summary>Replace the clipboard contents with <paramref name="text"/>.</summary>
    void SetText(string text);

    /// <summary>Empty the clipboard (used to restore when the original held no text).</summary>
    void Clear();

    /// <summary>
    /// Simulate Ctrl+V into the focused application. Returns <c>true</c> if the paste
    /// keystrokes were injected; <c>false</c> if the OS blocked them (e.g. an elevated
    /// foreground window), so the caller can leave the text on the clipboard instead of
    /// restoring over it and silently losing the user's words.
    /// </summary>
    bool SendPaste();
}
