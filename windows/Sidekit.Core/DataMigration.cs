namespace Sidekit.Core;

/// <summary>
/// One-time relocation of per-user data from the former "SpeakType" folders to the current
/// app-name folders, run once at startup. Pure given its inputs (the roots are injected), so it is
/// unit-tested against temp directories. Each move happens only when the source exists and the
/// destination does not — it never clobbers current data and is idempotent across launches.
/// Best-effort: a failure is swallowed so a rename can never block launch; the returned labels say
/// what moved.
/// </summary>
public static class DataMigration
{
    private const string LegacyName = "SpeakType";

    /// <summary>
    /// Move <c>{root}/{legacyName}</c> → <c>{root}/{currentName}</c> under both the roaming and local
    /// roots, each only when the source exists and the destination does not.
    /// </summary>
    /// <returns>Labels of what moved (<c>"roaming"</c>, <c>"local"</c>); empty when nothing moved.</returns>
    public static IReadOnlyList<string> Migrate(string roamingRoot, string localRoot,
                                                string legacyName, string currentName)
    {
        var moved = new List<string>();
        if (Relocate(Path.Combine(roamingRoot, legacyName), Path.Combine(roamingRoot, currentName)))
        {
            moved.Add("roaming");
        }

        if (Relocate(Path.Combine(localRoot, legacyName), Path.Combine(localRoot, currentName)))
        {
            moved.Add("local");
        }

        return moved;
    }

    /// <summary>
    /// Relocate the real per-user roots (<c>%AppData%</c> and <c>%LocalAppData%</c>) from the legacy
    /// "SpeakType" name to <paramref name="currentName"/>. Call once at startup, before any
    /// settings/model/log path is read.
    /// </summary>
    public static void MigrateLegacyAppData(string currentName)
    {
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Migrate(roaming, local, LegacyName, currentName);
    }

    private static bool Relocate(string from, string to)
    {
        if (!Directory.Exists(from) || Directory.Exists(to))
        {
            return false;
        }

        try
        {
            Directory.GetParent(to)?.Create();
            Directory.Move(from, to);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
