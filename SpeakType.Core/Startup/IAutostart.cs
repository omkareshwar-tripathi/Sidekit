namespace SpeakType.Core.Startup;

/// <summary>
/// Start-at-login registration (spec Feature 6 "Start with Windows"). The cross-platform
/// port; the Windows adapter writes the per-user Run key. The composition root applies the
/// spec default (ON) on first run and toggles it from the tray/Settings switch.
/// </summary>
public interface IAutostart
{
    /// <summary>True if SpeakType is registered to start at login.</summary>
    bool IsEnabled();

    /// <summary>Registers SpeakType to start at login (idempotent).</summary>
    void Enable();

    /// <summary>Removes the start-at-login registration (idempotent — no-op if absent).</summary>
    void Disable();
}
