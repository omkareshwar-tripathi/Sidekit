namespace SpeakType.Core.Settings;

/// <summary>
/// User-configurable application settings, persisted as JSON. Property
/// initializers supply the defaults so that omitted JSON keys keep their
/// default value when deserializing.
/// </summary>
public sealed class AppSettings
{
    /// <summary>Default push-to-talk hotkey (spec: Right Ctrl). Single source of truth.</summary>
    public const string DefaultHotkey = "RightCtrl";

    /// <summary>Default Whisper model (spec: base.en). Single source of truth.</summary>
    public const string DefaultModelSize = "base.en";

    public string Hotkey { get; set; } = DefaultHotkey;
    public string ModelSize { get; set; } = DefaultModelSize;
    public bool FillerRemoval { get; set; } = true;
    public bool SpellCorrection { get; set; } = true;
    public bool Overlay { get; set; } = true;
    public bool Autostart { get; set; } = true;
    public bool DebugLogging { get; set; } = false;

    /// <summary>
    /// Coerces a loaded settings object to a usable baseline, regardless of where it
    /// came from: any blank/whitespace string field (including an explicit JSON
    /// <c>null</c> in a hand-edited file, which would otherwise leave a non-nullable
    /// string holding null) falls back to its default. Full value validation — which
    /// hotkey combos or model sizes are actually allowed — is a later brick's job;
    /// this only guards against empty/null values.
    /// </summary>
    public void Normalize()
    {
        if (string.IsNullOrWhiteSpace(Hotkey))
        {
            Hotkey = DefaultHotkey;
        }

        if (string.IsNullOrWhiteSpace(ModelSize))
        {
            ModelSize = DefaultModelSize;
        }
    }
}
