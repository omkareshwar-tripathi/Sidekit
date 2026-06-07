using SpeakType.Core.Input;

namespace SpeakType.Tests.Input;

public sealed class HotkeyResolveTests
{
    [Fact]
    public void Resolve_returns_persisted_when_valid()
    {
        var hotkey = Hotkey.Resolve("Ctrl+Space", "RightCtrl");

        Assert.Equal("Ctrl+Space", hotkey.ToString());
    }

    [Fact]
    public void Resolve_falls_back_when_persisted_invalid()
    {
        var hotkey = Hotkey.Resolve("E", "RightCtrl");

        Assert.Equal("RightCtrl", hotkey.ToString());
    }

    [Fact]
    public void Resolve_falls_back_when_persisted_null()
    {
        var hotkey = Hotkey.Resolve(null, "RightCtrl");

        Assert.Equal("RightCtrl", hotkey.ToString());
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Resolve_falls_back_when_persisted_blank(string? persisted)
    {
        var hotkey = Hotkey.Resolve(persisted, "RightCtrl");

        Assert.Equal("RightCtrl", hotkey.ToString());
    }

    [Fact]
    public void Resolve_throws_when_fallback_invalid()
    {
        var ex = Assert.Throws<ArgumentException>(() => Hotkey.Resolve("E", "E"));

        Assert.Contains("fallback", ex.Message, StringComparison.OrdinalIgnoreCase);
    }
}
