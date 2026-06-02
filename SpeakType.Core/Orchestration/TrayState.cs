namespace SpeakType.Core.Orchestration;

/// <summary>The tray icon's visual state. Idle/Recording mirror the like-named
/// recording states; Busy covers transcribe+paste; Error is set explicitly by the
/// app's exception handler (spec Feature 6).</summary>
public enum TrayState { Idle, Recording, Busy, Error }

public static class TrayStatus
{
    /// <summary>Maps the dictation state machine to the tray's visual state.
    /// Transcribing and Pasting both read as Busy; Error is set explicitly by the
    /// app's exception handler, never produced from a RecordingState.</summary>
    public static TrayState From(RecordingState state) => state switch
    {
        RecordingState.Idle => TrayState.Idle,
        RecordingState.Recording => TrayState.Recording,
        RecordingState.Transcribing => TrayState.Busy,
        RecordingState.Pasting => TrayState.Busy,
        _ => throw new ArgumentOutOfRangeException(nameof(state), state, null),
    };
}
