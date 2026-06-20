using Sidekit.Core;

namespace Sidekit.Tests;

/// <summary>
/// Tests for the one-time legacy "SpeakType" → "Sidekit" per-user data relocation. Each runs
/// against throwaway temp roots so it never touches the real %AppData% / %LocalAppData%.
/// </summary>
public sealed class DataMigrationTests
{
    private static string TempRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "sidekit-mig-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    [Fact]
    public void Moves_legacy_folders_when_current_absent()
    {
        var roaming = TempRoot();
        var local = TempRoot();
        try
        {
            Directory.CreateDirectory(Path.Combine(roaming, "SpeakType"));
            File.WriteAllText(Path.Combine(roaming, "SpeakType", "settings.json"), "x");
            Directory.CreateDirectory(Path.Combine(local, "SpeakType", "models"));
            File.WriteAllText(Path.Combine(local, "SpeakType", "models", "m.bin"), "y");

            var moved = DataMigration.Migrate(roaming, local, "SpeakType", "Sidekit");

            Assert.Contains("roaming", moved);
            Assert.Contains("local", moved);
            Assert.True(File.Exists(Path.Combine(roaming, "Sidekit", "settings.json")));
            Assert.True(File.Exists(Path.Combine(local, "Sidekit", "models", "m.bin")));
            Assert.False(Directory.Exists(Path.Combine(roaming, "SpeakType")));
        }
        finally
        {
            Directory.Delete(roaming, recursive: true);
            Directory.Delete(local, recursive: true);
        }
    }

    [Fact]
    public void Does_not_clobber_when_current_already_exists()
    {
        var roaming = TempRoot();
        var local = TempRoot();
        try
        {
            Directory.CreateDirectory(Path.Combine(roaming, "SpeakType"));
            File.WriteAllText(Path.Combine(roaming, "SpeakType", "settings.json"), "old");
            Directory.CreateDirectory(Path.Combine(roaming, "Sidekit"));
            File.WriteAllText(Path.Combine(roaming, "Sidekit", "settings.json"), "new");

            var moved = DataMigration.Migrate(roaming, local, "SpeakType", "Sidekit");

            Assert.DoesNotContain("roaming", moved);
            Assert.Equal("new", File.ReadAllText(Path.Combine(roaming, "Sidekit", "settings.json")));
            Assert.True(Directory.Exists(Path.Combine(roaming, "SpeakType")));
        }
        finally
        {
            Directory.Delete(roaming, recursive: true);
            Directory.Delete(local, recursive: true);
        }
    }

    [Fact]
    public void No_op_on_clean_install()
    {
        var roaming = TempRoot();
        var local = TempRoot();
        try
        {
            var moved = DataMigration.Migrate(roaming, local, "SpeakType", "Sidekit");

            Assert.Empty(moved);
            Assert.False(Directory.Exists(Path.Combine(roaming, "Sidekit")));
        }
        finally
        {
            Directory.Delete(roaming, recursive: true);
            Directory.Delete(local, recursive: true);
        }
    }
}
