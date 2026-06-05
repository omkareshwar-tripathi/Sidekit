using SpeakType.Core;
using SpeakType.Core.Logging;
using SpeakType.Core.Models;
using SpeakType.Core.Settings;

namespace SpeakType.Tests;

/// <summary>
/// Guards that every per-user default path is built from <see cref="AppInfo.Name"/>, so renaming the
/// app moves the settings/models/logs folders together instead of leaving stragglers behind.
/// </summary>
public sealed class DefaultPathsTests
{
    [Fact]
    public void Settings_default_path_lives_under_the_app_name_folder()
    {
        Assert.EndsWith(Path.Combine(AppInfo.Name, "settings.json"), JsonSettingsStore.DefaultFilePath);
    }

    [Fact]
    public void Models_default_directory_lives_under_the_app_name_folder()
    {
        Assert.EndsWith(Path.Combine(AppInfo.Name, "models"), ModelStore.DefaultModelsDirectory);
    }

    [Fact]
    public void Log_default_path_lives_under_the_app_name_folder()
    {
        Assert.EndsWith(Path.Combine(AppInfo.Name, "logs", "speaktype.log"), FileLogSink.DefaultLogPath);
    }
}
