namespace Sidekit.Core.Settings;

/// <summary>
/// Loads and persists <see cref="AppSettings"/>.
/// </summary>
public interface ISettingsStore
{
    AppSettings Load();
    void Save(AppSettings settings);
}
