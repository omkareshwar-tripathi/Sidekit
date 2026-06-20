using Sidekit.Core.Input;

namespace Sidekit.WinApp.Input;

/// <summary>
/// Maps a parsed <see cref="Hotkey"/> to the Win32 virtual-key (VK) codes a low-level
/// keyboard hook sees. Pure lookup — no P/Invoke. "Either side satisfies": where a token
/// is side-agnostic (e.g. bare "Ctrl" or the Ctrl modifier flag), the result lists both
/// the left and right VKs and a match on either counts.
/// </summary>
internal static class KeyCodes
{
    // Modifier VKs (Win32 winuser.h).
    private const uint VK_LSHIFT = 0xA0;
    private const uint VK_RSHIFT = 0xA1;
    private const uint VK_LCONTROL = 0xA2;
    private const uint VK_RCONTROL = 0xA3;
    private const uint VK_LMENU = 0xA4; // Left Alt
    private const uint VK_RMENU = 0xA5; // Right Alt

    // Bare-modifier triggers → the VK(s) that fire that exact key.
    private static readonly Dictionary<string, uint[]> ModifierTriggers =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["Ctrl"] = new[] { VK_LCONTROL, VK_RCONTROL },
            ["LeftCtrl"] = new[] { VK_LCONTROL },
            ["RightCtrl"] = new[] { VK_RCONTROL },
            ["Alt"] = new[] { VK_LMENU, VK_RMENU },
            ["LeftAlt"] = new[] { VK_LMENU },
            ["RightAlt"] = new[] { VK_RMENU },
            ["Shift"] = new[] { VK_LSHIFT, VK_RSHIFT },
            ["LeftShift"] = new[] { VK_LSHIFT },
            ["RightShift"] = new[] { VK_RSHIFT },
        };

    // Named non-modifier keys → their single VK.
    private static readonly Dictionary<string, uint> NamedKeys =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["Pause"] = 0x13,
            ["Space"] = 0x20,
            ["Enter"] = 0x0D,
            ["Tab"] = 0x09,
            ["Esc"] = 0x1B,
            ["Backspace"] = 0x08,
            ["Delete"] = 0x2E,
            ["Insert"] = 0x2D,
            ["Home"] = 0x24,
            ["End"] = 0x23,
            ["PageUp"] = 0x21,
            ["PageDown"] = 0x22,
            ["Up"] = 0x26,
            ["Down"] = 0x28,
            ["Left"] = 0x25,
            ["Right"] = 0x27,
        };

    /// <summary>
    /// VK code(s) for the hotkey's trigger key. More than one when the trigger is a
    /// side-agnostic bare modifier (e.g. "Ctrl" → both LCONTROL and RCONTROL).
    /// </summary>
    public static uint[] TriggerKey(Hotkey hotkey)
    {
        var t = hotkey.TriggerKey;

        if (ModifierTriggers.TryGetValue(t, out var modVks))
        {
            return modVks;
        }

        if (NamedKeys.TryGetValue(t, out var named))
        {
            return new[] { named };
        }

        // F1–F24: VK_F1 = 0x70 … VK_F24 = 0x87.
        if (t.Length >= 2 && (t[0] == 'F' || t[0] == 'f') && int.TryParse(t[1..], out var n)
            && n is >= 1 and <= 24)
        {
            return new[] { (uint)(0x70 + n - 1) };
        }

        // Single letter A–Z → 0x41–0x5A; single digit 0–9 → 0x30–0x39 (VK == ASCII).
        if (t.Length == 1 && (char.IsAsciiLetterUpper(t[0]) || char.IsAsciiDigit(t[0])))
        {
            return new[] { (uint)t[0] };
        }

        throw new ArgumentException($"Unmappable trigger key '{t}'.", nameof(hotkey));
    }

    /// <summary>
    /// One VK set per required modifier flag; a group is satisfied when ANY of its VKs is
    /// held (either side). Empty when the hotkey has no modifiers.
    /// </summary>
    public static IReadOnlyList<uint[]> HotkeyModifiers(Hotkey hotkey)
    {
        var groups = new List<uint[]>();

        if (hotkey.Modifiers.HasFlag(Core.Input.HotkeyModifiers.Ctrl))
        {
            groups.Add(new[] { VK_LCONTROL, VK_RCONTROL });
        }

        if (hotkey.Modifiers.HasFlag(Core.Input.HotkeyModifiers.Alt))
        {
            groups.Add(new[] { VK_LMENU, VK_RMENU });
        }

        if (hotkey.Modifiers.HasFlag(Core.Input.HotkeyModifiers.Shift))
        {
            groups.Add(new[] { VK_LSHIFT, VK_RSHIFT });
        }

        return groups;
    }
}
