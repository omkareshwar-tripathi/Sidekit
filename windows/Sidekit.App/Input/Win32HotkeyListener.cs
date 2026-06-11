using System.Runtime.InteropServices;
using Sidekit.Core.Input;

namespace Sidekit.App.Input;

/// <summary>
/// Windows <see cref="IHotkeyListener"/> backed by a <c>WH_KEYBOARD_LL</c> low-level
/// keyboard hook. Tracks which modifier keys are currently held; when the bound trigger
/// goes down with every required modifier group satisfied it raises <see cref="Pressed"/>
/// and swallows the trigger event (so the key never reaches the focused app), then raises
/// <see cref="Released"/> and swallows the matching key-up. Standalone modifier keys are
/// never swallowed. <see cref="Pause"/> passes everything through for the session.
/// </summary>
public sealed partial class Win32HotkeyListener : IHotkeyListener, IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int HC_ACTION = 0;
    private const uint WM_KEYDOWN = 0x0100;
    private const uint WM_KEYUP = 0x0101;
    private const uint WM_SYSKEYDOWN = 0x0104;
    private const uint WM_SYSKEYUP = 0x0105;

    // The managed delegate must stay rooted for the lifetime of the hook, else the GC
    // could collect it and the native callback would crash.
    private readonly LowLevelKeyboardProc _proc;
    private readonly HashSet<uint> _heldModifiers = new();

    private nint _hookHandle;
    private uint[] _triggerVks;
    private IReadOnlyList<uint[]> _requiredModifierGroups;
    private bool _active;
    private bool _paused;
    private bool _disposed;

    public Win32HotkeyListener(Hotkey hotkey)
    {
        _triggerVks = KeyCodes.TriggerKey(hotkey);
        _requiredModifierGroups = KeyCodes.HotkeyModifiers(hotkey);
        _proc = HookCallback;

        var moduleHandle = GetModuleHandleW(null);
        _hookHandle = SetWindowsHookExW(WH_KEYBOARD_LL, _proc, moduleHandle, 0);
        if (_hookHandle == 0)
        {
            throw new InvalidOperationException(
                $"Failed to install keyboard hook (Win32 error {Marshal.GetLastPInvokeError()}).");
        }
    }

    public event EventHandler? Pressed;

    public event EventHandler? Released;

    /// <summary>True while Pause is in effect (session-only; not persisted).</summary>
    public bool Paused => _paused;

    /// <summary>
    /// Swap the active binding without re-installing the hook. Resets held/active state.
    /// If called mid-hold, <see cref="Released"/> will NOT fire for the in-progress press —
    /// the consumer (Brick 14) must treat a rebind as a cancel of any active capture.
    /// </summary>
    public void Rebind(Hotkey hotkey)
    {
        _triggerVks = KeyCodes.TriggerKey(hotkey);
        _requiredModifierGroups = KeyCodes.HotkeyModifiers(hotkey);
        _heldModifiers.Clear();
        _active = false;
    }

    /// <summary>
    /// Stop reacting for this session: pass all events through, never raise/suppress.
    /// If called mid-hold, <see cref="Released"/> will NOT fire for the in-progress press —
    /// the consumer (Brick 14) must treat a pause as a cancel of any active capture.
    /// </summary>
    public void Pause()
    {
        _paused = true;
        _heldModifiers.Clear();
        _active = false;
    }

    /// <summary>Resume reacting after a <see cref="Pause"/>.</summary>
    public void Resume() => _paused = false;

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        if (_hookHandle != 0)
        {
            UnhookWindowsHookEx(_hookHandle);
            _hookHandle = 0;
        }

        GC.SuppressFinalize(this);
    }

    private nint HookCallback(int nCode, nuint wParam, nint lParam)
    {
        if (nCode != HC_ACTION || _paused)
        {
            return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
        }

        // This callback runs on every system-wide keystroke; vkCode is the first DWORD of
        // KBDLLHOOKSTRUCT, so read just those 4 bytes instead of copying the whole struct.
        var vk = (uint)Marshal.ReadInt32(lParam);
        var msg = (uint)wParam;
        var isDown = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
        var isUp = msg is WM_KEYUP or WM_SYSKEYUP;

        // Track held modifier keys (any of the six L/R Ctrl/Alt/Shift VKs).
        if (IsModifierVk(vk))
        {
            if (isDown)
            {
                _heldModifiers.Add(vk);
            }
            else if (isUp)
            {
                _heldModifiers.Remove(vk);
            }
        }

        var isTrigger = Array.IndexOf(_triggerVks, vk) >= 0;

        if (isTrigger && isDown && (_active || ModifiersSatisfied()))
        {
            if (!_active)
            {
                _active = true;
                Pressed?.Invoke(this, EventArgs.Empty);
            }

            // Suppress the trigger key-down on the first press AND every auto-repeat while
            // held, so a long hold never leaks repeated key-downs into the focused app.
            return 1;
        }

        if (isTrigger && isUp && _active)
        {
            _active = false;
            Released?.Invoke(this, EventArgs.Empty);
            return 1; // suppress the matching key-up so it doesn't leak
        }

        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    private bool ModifiersSatisfied()
    {
        foreach (var group in _requiredModifierGroups)
        {
            var anyHeld = false;
            foreach (var modVk in group)
            {
                if (_heldModifiers.Contains(modVk))
                {
                    anyHeld = true;
                    break;
                }
            }

            if (!anyHeld)
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsModifierVk(uint vk) => vk is >= 0xA0 and <= 0xA5;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint LowLevelKeyboardProc(int nCode, nuint wParam, nint lParam);

    // SetWindowsHookEx takes a managed delegate, which the [LibraryImport] source generator
    // cannot marshal (SYSLIB1051). Keep [DllImport] for this one and suppress the
    // "convert to LibraryImport" suggestion so TreatWarningsAsErrors stays satisfied.
#pragma warning disable SYSLIB1054
    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookExW(
        int idHook, LowLevelKeyboardProc lpfn, nint hMod, uint dwThreadId);
#pragma warning restore SYSLIB1054

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnhookWindowsHookEx(nint hhk);

    [LibraryImport("user32.dll")]
    private static partial nint CallNextHookEx(nint hhk, int nCode, nuint wParam, nint lParam);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint GetModuleHandleW(string? lpModuleName);
}
