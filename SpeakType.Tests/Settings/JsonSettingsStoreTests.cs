using System;
using System.IO;
using SpeakType.Core.Settings;

namespace SpeakType.Tests.Settings;

public sealed class JsonSettingsStoreTests : IDisposable
{
    private readonly string _tempDir;

    public JsonSettingsStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "speaktype-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private string PathFor(string name) => Path.Combine(_tempDir, name);

    [Fact]
    public void Save_then_Load_round_trips_all_properties()
    {
        var path = PathFor("settings.json");
        var store = new JsonSettingsStore(path);
        var saved = new AppSettings
        {
            Hotkey = "Ctrl+Space",
            ModelSize = "small.en",
            FillerRemoval = false,
            Overlay = false,
            Autostart = false,
            DebugLogging = true,
        };

        store.Save(saved);
        var loaded = store.Load();

        Assert.Equal("Ctrl+Space", loaded.Hotkey);
        Assert.Equal("small.en", loaded.ModelSize);
        Assert.False(loaded.FillerRemoval);
        Assert.False(loaded.Overlay);
        Assert.False(loaded.Autostart);
        Assert.True(loaded.DebugLogging);
    }

    [Fact]
    public void Load_missing_file_returns_defaults()
    {
        var store = new JsonSettingsStore(PathFor("does-not-exist.json"));

        var loaded = store.Load();

        var defaults = new AppSettings();
        Assert.Equal(defaults.Hotkey, loaded.Hotkey);
        Assert.Equal(defaults.ModelSize, loaded.ModelSize);
        Assert.Equal(defaults.FillerRemoval, loaded.FillerRemoval);
        Assert.Equal(defaults.Overlay, loaded.Overlay);
        Assert.Equal(defaults.Autostart, loaded.Autostart);
        Assert.Equal(defaults.DebugLogging, loaded.DebugLogging);
    }

    [Fact]
    public void Load_partial_file_fills_gaps_with_defaults()
    {
        var path = PathFor("settings.json");
        File.WriteAllText(path, "{ \"modelSize\": \"small.en\" }");
        var store = new JsonSettingsStore(path);

        var loaded = store.Load();

        var defaults = new AppSettings();
        Assert.Equal("small.en", loaded.ModelSize);
        Assert.Equal(defaults.Hotkey, loaded.Hotkey);
        Assert.Equal(defaults.FillerRemoval, loaded.FillerRemoval);
        Assert.Equal(defaults.Overlay, loaded.Overlay);
        Assert.Equal(defaults.Autostart, loaded.Autostart);
        Assert.Equal(defaults.DebugLogging, loaded.DebugLogging);
    }

    [Fact]
    public void Load_corrupt_file_returns_defaults_without_throwing()
    {
        var path = PathFor("settings.json");
        File.WriteAllText(path, "{ not valid json");
        var store = new JsonSettingsStore(path);

        var loaded = store.Load();

        Assert.Equal(new AppSettings().Hotkey, loaded.Hotkey);
        Assert.Equal(new AppSettings().ModelSize, loaded.ModelSize);
    }

    [Fact]
    public void Load_blank_hotkey_is_normalized_to_default()
    {
        var path = PathFor("settings.json");
        File.WriteAllText(path, "{ \"hotkey\": \"   \" }");
        var store = new JsonSettingsStore(path);

        var loaded = store.Load();

        Assert.Equal(AppSettings.DefaultHotkey, loaded.Hotkey);
    }

    [Fact]
    public void Load_explicit_null_string_fields_are_normalized_to_defaults()
    {
        // A hand-edited file with explicit JSON null would otherwise leave the
        // non-nullable string properties holding null (NRE waiting to happen).
        var path = PathFor("settings.json");
        File.WriteAllText(path, "{ \"hotkey\": null, \"modelSize\": null }");
        var store = new JsonSettingsStore(path);

        var loaded = store.Load();

        Assert.Equal(AppSettings.DefaultHotkey, loaded.Hotkey);
        Assert.Equal(AppSettings.DefaultModelSize, loaded.ModelSize);
    }

    [Fact]
    public void Load_file_containing_literal_null_returns_defaults()
    {
        // JsonSerializer.Deserialize returns null for the text "null"; the store
        // must fall back to defaults rather than Normalize() a null reference.
        var path = PathFor("settings.json");
        File.WriteAllText(path, "null");
        var store = new JsonSettingsStore(path);

        var loaded = store.Load();

        Assert.Equal(AppSettings.DefaultHotkey, loaded.Hotkey);
        Assert.Equal(AppSettings.DefaultModelSize, loaded.ModelSize);
    }

    [Fact]
    public void Save_creates_missing_parent_directory()
    {
        var path = Path.Combine(_tempDir, "nested", "sub", "settings.json");
        var store = new JsonSettingsStore(path);

        store.Save(new AppSettings());

        Assert.True(File.Exists(path));
    }

    [Fact]
    public void Save_writes_camelCase_json_keys()
    {
        var path = PathFor("settings.json");
        var store = new JsonSettingsStore(path);

        store.Save(new AppSettings());
        var text = File.ReadAllText(path);

        // All six keys must be camelCase, and no PascalCase key should leak.
        Assert.Contains("\"hotkey\"", text);
        Assert.Contains("\"modelSize\"", text);
        Assert.Contains("\"fillerRemoval\"", text);
        Assert.Contains("\"overlay\"", text);
        Assert.Contains("\"autostart\"", text);
        Assert.Contains("\"debugLogging\"", text);
        Assert.DoesNotContain("\"Hotkey\"", text);
        Assert.DoesNotContain("\"ModelSize\"", text);
    }
}
