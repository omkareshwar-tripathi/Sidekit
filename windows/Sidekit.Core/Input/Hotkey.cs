using System.Text.RegularExpressions;

namespace Sidekit.Core.Input;

/// <summary>Modifier keys held as part of a hotkey combo (side-agnostic).</summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Ctrl = 1,
    Alt = 2,
    Shift = 4,
}

/// <summary>
/// A parsed, validated push-to-talk hotkey: zero or more <see cref="Modifiers"/> plus a
/// single <see cref="TriggerKey"/> (a canonical key token, e.g. "RightCtrl", "Space", "F13").
/// Pure — maps no virtual-key codes; the Win32 adapter (Brick 4b) maps TriggerKey → VK.
/// </summary>
public sealed record Hotkey(HotkeyModifiers Modifiers, string TriggerKey)
{
    // Modifier aliases → (canonical name, generic flag). A part in this table is a
    // modifier; anything else is a trigger candidate. Spec allows bare Right/Left Ctrl,
    // Right/Left Alt, and Shift; in a combo either side folds into the side-agnostic flag.
    private static readonly Dictionary<string, (string Canonical, HotkeyModifiers Flag)> ModifierAliases =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["ctrl"] = ("Ctrl", HotkeyModifiers.Ctrl),
            ["control"] = ("Ctrl", HotkeyModifiers.Ctrl),
            ["leftctrl"] = ("LeftCtrl", HotkeyModifiers.Ctrl),
            ["rightctrl"] = ("RightCtrl", HotkeyModifiers.Ctrl),
            ["alt"] = ("Alt", HotkeyModifiers.Alt),
            ["leftalt"] = ("LeftAlt", HotkeyModifiers.Alt),
            ["rightalt"] = ("RightAlt", HotkeyModifiers.Alt),
            ["shift"] = ("Shift", HotkeyModifiers.Shift),
            ["leftshift"] = ("LeftShift", HotkeyModifiers.Shift),
            ["rightshift"] = ("RightShift", HotkeyModifiers.Shift),
        };

    // Named non-modifier keys → canonical name. None of these are valid bare triggers.
    private static readonly Dictionary<string, string> NamedKeys =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["space"] = "Space",
            ["enter"] = "Enter",
            ["return"] = "Enter",
            ["tab"] = "Tab",
            ["esc"] = "Esc",
            ["escape"] = "Esc",
            ["backspace"] = "Backspace",
            ["delete"] = "Delete",
            ["del"] = "Delete",
            ["insert"] = "Insert",
            ["ins"] = "Insert",
            ["home"] = "Home",
            ["end"] = "End",
            ["pageup"] = "PageUp",
            ["pgup"] = "PageUp",
            ["pagedown"] = "PageDown",
            ["pgdn"] = "PageDown",
            ["up"] = "Up",
            ["down"] = "Down",
            ["left"] = "Left",
            ["right"] = "Right",
        };

    // Pause/Break aliases → canonical "Pause" (a valid bare trigger).
    private static readonly HashSet<string> PauseKeys =
        new(StringComparer.OrdinalIgnoreCase) { "pause", "break", "pause/break", "pausebreak" };

    private static readonly Regex FKey = new("^F([1-9]|1[0-9]|2[0-4])$", RegexOptions.IgnoreCase);

    /// <summary>
    /// Parse a hotkey string (e.g. "RightCtrl", "Ctrl+Space", "F13"). Case-insensitive,
    /// '+'-separated. Returns false with a user-facing <paramref name="error"/> when the
    /// binding is disallowed (bare letter/digit, bare F1–F12, no main key, etc.).
    /// </summary>
    public static bool TryParse(string? text, out Hotkey? hotkey, out string? error)
    {
        hotkey = null;

        if (string.IsNullOrWhiteSpace(text))
        {
            error = "Hotkey is empty.";
            return false;
        }

        var parts = text.Split('+');
        for (var i = 0; i < parts.Length; i++)
        {
            parts[i] = parts[i].Trim();
            if (parts[i].Length == 0)
            {
                error = "Hotkey has an empty key.";
                return false;
            }
        }

        var mods = HotkeyModifiers.None;
        string? soleModifierCanonical = null;
        var triggers = new List<string>();
        foreach (var part in parts)
        {
            if (ModifierAliases.TryGetValue(part, out var modifier))
            {
                mods |= modifier.Flag;
                soleModifierCanonical = modifier.Canonical;
            }
            else
            {
                triggers.Add(part);
            }
        }

        if (triggers.Count >= 2)
        {
            error = "A hotkey can have only one main key.";
            return false;
        }

        if (triggers.Count == 0)
        {
            // The only no-trigger binding allowed is a single bare modifier (e.g. RightCtrl),
            // where that lone part is itself the trigger key. Two+ modifiers need a main key.
            if (parts.Length == 1)
            {
                hotkey = new Hotkey(HotkeyModifiers.None, soleModifierCanonical!);
                error = null;
                return true;
            }

            error = "A combo needs a non-modifier key (e.g. Ctrl+Space).";
            return false;
        }

        var t = triggers[0];
        var bare = mods == HotkeyModifiers.None;

        if (FKey.IsMatch(t))
        {
            var canonical = t.ToUpperInvariant();
            var number = int.Parse(canonical[1..]);
            if (bare && number <= 12)
            {
                error = "Use F13–F24, or add a modifier (e.g. Ctrl+F1).";
                return false;
            }

            return Accept(mods, canonical, out hotkey, out error);
        }

        if (PauseKeys.Contains(t))
        {
            return Accept(mods, "Pause", out hotkey, out error);
        }

        if (t.Length == 1 && (char.IsAsciiLetter(t[0]) || char.IsAsciiDigit(t[0])))
        {
            if (bare)
            {
                error = "A bare letter or digit can't be a hotkey — add a modifier " +
                    "(e.g. Ctrl+E) or use a function key like F13.";
                return false;
            }

            // Upper-case the letter for a canonical token; a no-op for digits.
            return Accept(mods, t.ToUpperInvariant(), out hotkey, out error);
        }

        if (NamedKeys.TryGetValue(t, out var named))
        {
            if (bare)
            {
                error = $"'{named}' needs a modifier (e.g. Ctrl+{named}).";
                return false;
            }

            return Accept(mods, named, out hotkey, out error);
        }

        error = $"Unrecognized key '{t}'.";
        return false;
    }

    /// <summary>
    /// Resolves a persisted hotkey string to a valid <see cref="Hotkey"/>. Returns the parsed
    /// <paramref name="persisted"/> value when it is valid; otherwise falls back to
    /// <paramref name="fallback"/> (the app's compile-time default, which must itself be valid).
    /// Used at the seam where a stored setting becomes a real binding — AppSettings.Normalize()
    /// only null-guards, so a hand-edited bad value (e.g. "E") would otherwise reach the hook.
    /// </summary>
    public static Hotkey Resolve(string? persisted, string fallback)
    {
        if (TryParse(persisted, out var parsed, out _))
        {
            return parsed!;
        }

        if (TryParse(fallback, out var parsedFallback, out _))
        {
            return parsedFallback!;
        }

        throw new ArgumentException(
            $"The fallback hotkey '{fallback}' is not a valid hotkey.", nameof(fallback));
    }

    /// <summary>Canonical round-trippable form, e.g. "Ctrl+Shift+F1" or "RightCtrl".</summary>
    public override string ToString()
    {
        var prefix = "";
        if (Modifiers.HasFlag(HotkeyModifiers.Ctrl))
        {
            prefix += "Ctrl+";
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            prefix += "Alt+";
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            prefix += "Shift+";
        }

        return prefix + TriggerKey;
    }

    private static bool Accept(
        HotkeyModifiers mods, string trigger, out Hotkey? hotkey, out string? error)
    {
        hotkey = new Hotkey(mods, trigger);
        error = null;
        return true;
    }
}
