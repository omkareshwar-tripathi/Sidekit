using Microsoft.Win32;
using SpeakType.Core;
using SpeakType.Core.Startup;

namespace SpeakType.App.Startup;

/// <summary>
/// Windows adapter for <see cref="IAutostart"/> (spec Feature 6 "Start with Windows", also
/// exposed in Settings). Registers SpeakType under the per-user HKCU Run key
/// (<c>Software\Microsoft\Windows\CurrentVersion\Run</c>), so it launches at login without
/// admin rights. The composition root applies the spec default (ON) on first run.
/// </summary>
public sealed class WinAutostart : IAutostart
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(AppInfo.Name) is not null;
    }

    public void Enable()
    {
        var path = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine the executable path for autostart.");

        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        // Quote the path so a Program Files install (spaces) launches correctly.
        key.SetValue(AppInfo.Name, $"\"{path}\"");
    }

    public void Disable()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
        key?.DeleteValue(AppInfo.Name, throwOnMissingValue: false);
    }
}
