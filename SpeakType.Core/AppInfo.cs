namespace SpeakType.Core;

/// <summary>
/// Static identity for the app. Used later for the single-instance mutex name,
/// the About box, and the %APPDATA%\SpeakType / %LOCALAPPDATA%\SpeakType paths.
/// </summary>
public static class AppInfo
{
    public const string Name = "SpeakType";
}
