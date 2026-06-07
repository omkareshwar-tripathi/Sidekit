using SpeakType.Core.Input;

namespace SpeakType.Tests.Input;

public sealed class HotkeyTests
{
    [Theory]
    [InlineData("RightCtrl", HotkeyModifiers.None, "RightCtrl")]
    [InlineData("rightctrl", HotkeyModifiers.None, "RightCtrl")]
    [InlineData("LeftAlt", HotkeyModifiers.None, "LeftAlt")]
    [InlineData("Shift", HotkeyModifiers.None, "Shift")]
    [InlineData("F13", HotkeyModifiers.None, "F13")]
    [InlineData("F24", HotkeyModifiers.None, "F24")]
    [InlineData("Pause", HotkeyModifiers.None, "Pause")]
    [InlineData("Ctrl+Space", HotkeyModifiers.Ctrl, "Space")]
    [InlineData("ctrl+e", HotkeyModifiers.Ctrl, "E")]
    [InlineData("Ctrl+Shift+F1", HotkeyModifiers.Ctrl | HotkeyModifiers.Shift, "F1")]
    [InlineData("Alt+5", HotkeyModifiers.Alt, "5")]
    public void TryParse_accepts_valid_bindings(string text, HotkeyModifiers mods, string trigger)
    {
        var ok = Hotkey.TryParse(text, out var hotkey, out var error);

        Assert.True(ok);
        Assert.Null(error);
        Assert.NotNull(hotkey);
        Assert.Equal(mods, hotkey!.Modifiers);
        Assert.Equal(trigger, hotkey.TriggerKey);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    [InlineData("E")]
    [InlineData("5")]
    [InlineData("F1")]
    [InlineData("Space")]
    [InlineData("Ctrl+Shift")]
    [InlineData("Ctrl+A+B")]
    [InlineData("Ctrl+")]
    [InlineData("Ctrl+Foo")]
    public void TryParse_rejects_disallowed_bindings(string? text)
    {
        var ok = Hotkey.TryParse(text, out var hotkey, out var error);

        Assert.False(ok);
        Assert.Null(hotkey);
        Assert.False(string.IsNullOrEmpty(error));
    }

    [Theory]
    [InlineData("RightCtrl", "RightCtrl")]
    [InlineData("Ctrl+Space", "Ctrl+Space")]
    [InlineData("Ctrl+Shift+F1", "Ctrl+Shift+F1")]
    [InlineData("Alt+5", "Alt+5")]
    public void TryParse_round_trips_canonical_form(string input, string canonical)
    {
        Assert.True(Hotkey.TryParse(input, out var first, out _));
        Assert.Equal(canonical, first!.ToString());

        Assert.True(Hotkey.TryParse(first.ToString(), out var second, out _));
        Assert.Equal(first, second);
    }
}
