using System.Text.Json;

namespace SpeakType.Core.Settings;

/// <summary>
/// Stores <see cref="AppSettings"/> as a JSON file. Tolerates a missing or
/// corrupt file by falling back to defaults rather than throwing.
/// </summary>
public sealed class JsonSettingsStore : ISettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    private readonly string _filePath;

    public JsonSettingsStore(string filePath)
    {
        ArgumentException.ThrowIfNullOrEmpty(filePath);
        _filePath = filePath;
    }

    public static string DefaultFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "SpeakType",
        "settings.json");

    public AppSettings Load()
    {
        if (!File.Exists(_filePath))
        {
            return new AppSettings();
        }

        AppSettings settings;
        try
        {
            var json = File.ReadAllText(_filePath);
            settings = JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
        }
        catch (JsonException)
        {
            return new AppSettings();
        }

        settings.Normalize();
        return settings;
    }

    public void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(_filePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var json = JsonSerializer.Serialize(settings, Options);
        File.WriteAllText(_filePath, json);
    }
}
