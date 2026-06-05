namespace SpeakType.Core.Input;

/// <summary>
/// Push-to-talk hotkey source. <see cref="Pressed"/> fires when the key goes
/// down, <see cref="Released"/> when it comes back up.
/// </summary>
public interface IHotkeyListener
{
    event EventHandler? Pressed;
    event EventHandler? Released;
}
