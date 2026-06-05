using System.Runtime.InteropServices;
using SpeakType.Core.Paste;
using Clipboard = System.Windows.Forms.Clipboard;

namespace SpeakType.App.Paste;

/// <summary>
/// Windows <see cref="IClipboard"/> adapter. Text save/restore uses WinForms
/// <see cref="Clipboard"/>; Ctrl+V is injected via <c>SendInput</c>. The paste is always
/// attempted (no pre-check for an editable target); a return of <c>false</c> from
/// <see cref="SendPaste"/> means the OS blocked the keystroke, and the caller leaves the
/// text on the clipboard for a manual paste.
/// <para>
/// The WinForms <see cref="Clipboard"/> calls require an STA thread; Brick 14's
/// composition root must marshal <see cref="GetText"/>/<see cref="SetText"/>/<see cref="Clear"/>
/// (and thus the whole paste) onto the UI/STA thread.
/// </para>
/// </summary>
public sealed partial class WinClipboard : IClipboard
{
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint INPUT_KEYBOARD = 1;

    // Size of the marshalled INPUT struct, required by SendInput; constant per process.
    private static readonly int InputSize = Marshal.SizeOf<INPUT>();

    public string? GetText()
    {
        // One clipboard round-trip: GetText returns "" when there is no text.
        var text = Clipboard.GetText();
        return string.IsNullOrEmpty(text) ? null : text;
    }

    public void SetText(string text) => Clipboard.SetText(text);

    public void Clear() => Clipboard.Clear();

    public bool SendPaste()
    {
        var inputs = new[]
        {
            KeyInput(VK_CONTROL, 0),
            KeyInput(VK_V, 0),
            KeyInput(VK_V, KEYEVENTF_KEYUP),
            KeyInput(VK_CONTROL, KEYEVENTF_KEYUP),
        };

        // Returns the number of events injected; 0 (or short) means the OS blocked input
        // (e.g. an elevated foreground window) — report failure so we don't restore over our text.
        return SendInput((uint)inputs.Length, inputs, InputSize) == (uint)inputs.Length;
    }

    private static INPUT KeyInput(ushort vk, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = flags,
                time = 0,
                dwExtraInfo = 0,
            },
        },
    };

    // These interop structs are populated/read only by the marshaller, so most fields are
    // never touched in C# source — disable CS0649 ("never assigned") for the block. The
    // padding fields are load-bearing: they fix each struct's size/layout to the OS contract.
#pragma warning disable CS0649
    private struct INPUT
    {
        public uint type;
        public InputUnion u;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi; // largest member — sizes the union to match the OS INPUT
        [FieldOffset(0)] public KEYBDINPUT ki; // the only member we populate (Ctrl+V key events)
    }

    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public nuint dwExtraInfo;
    }

    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public nuint dwExtraInfo;
    }

#pragma warning restore CS0649

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial uint SendInput(uint nInputs, [In] INPUT[] pInputs, int cbSize);
}
