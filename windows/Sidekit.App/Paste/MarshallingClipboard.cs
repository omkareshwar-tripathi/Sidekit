using Sidekit.App.Threading;
using Sidekit.Core.Paste;

namespace Sidekit.App.Paste;

/// <summary>
/// Wraps an STA-only <see cref="IClipboard"/> (the WinForms-backed <see cref="WinClipboard"/>) so every
/// call runs on the UI thread. The dictation cycle runs on a background thread, but WinForms
/// <c>Clipboard</c> requires the STA UI thread; this hops each op there. The brief
/// <c>Thread.Sleep</c> inside <see cref="ClipboardPasteService"/> happens between these calls, on the
/// background thread, so the UI thread is never blocked waiting.
/// </summary>
internal sealed class MarshallingClipboard : IClipboard
{
    private readonly IClipboard _inner;
    private readonly UiMarshaller _ui;

    public MarshallingClipboard(IClipboard inner, UiMarshaller ui)
    {
        ArgumentNullException.ThrowIfNull(inner);
        ArgumentNullException.ThrowIfNull(ui);
        _inner = inner;
        _ui = ui;
    }

    public string? GetText() => _ui.Invoke(() => _inner.GetText());

    public void SetText(string text) => _ui.Invoke(() => _inner.SetText(text));

    public void Clear() => _ui.Invoke(() => _inner.Clear());

    public bool SendPaste() => _ui.Invoke(() => _inner.SendPaste());
}
