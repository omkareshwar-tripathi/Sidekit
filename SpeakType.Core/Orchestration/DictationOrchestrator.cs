using SpeakType.Core.Audio;
using SpeakType.Core.Cleanup;
using SpeakType.Core.Input;
using SpeakType.Core.Paste;
using SpeakType.Core.Settings;
using SpeakType.Core.Transcription;

namespace SpeakType.Core.Orchestration;

public enum RecordingState { Idle, Recording, Transcribing, Pasting }

/// <summary>Outcome of one dictation cycle, for the UI overlay to surface.</summary>
public enum DictationOutcome { Pasted, LeftOnClipboard, NoSpeech }

/// <summary>
/// State machine that wires the dictation pipeline: hotkey press starts capture,
/// release runs capture → transcribe → clean → paste and reports the outcome.
/// Concurrent hotkey events are ignored while a cycle is in flight (the
/// <see cref="State"/> guard), so each cycle runs to completion.
/// </summary>
public sealed class DictationOrchestrator
{
    private readonly IAudioCapture _audioCapture;
    private readonly ITranscriber _transcriber;
    private readonly IPasteService _pasteService;
    private readonly TranscriptCleaner _cleaner;
    private readonly AppSettings _settings;

    public DictationOrchestrator(
        IHotkeyListener hotkey,
        IAudioCapture audioCapture,
        ITranscriber transcriber,
        IPasteService pasteService,
        TranscriptCleaner cleaner,
        AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(hotkey);
        ArgumentNullException.ThrowIfNull(audioCapture);
        ArgumentNullException.ThrowIfNull(transcriber);
        ArgumentNullException.ThrowIfNull(pasteService);
        ArgumentNullException.ThrowIfNull(cleaner);
        ArgumentNullException.ThrowIfNull(settings);

        _audioCapture = audioCapture;
        _transcriber = transcriber;
        _pasteService = pasteService;
        _cleaner = cleaner;
        _settings = settings;

        hotkey.Pressed += OnPressed;
        hotkey.Released += OnReleased;
    }

    public RecordingState State { get; private set; } = RecordingState.Idle;

    /// <summary>Raised once at the end of every dictation cycle that produced an outcome.</summary>
    public event EventHandler<DictationOutcome>? Completed;

    private void OnPressed(object? sender, EventArgs e)
    {
        if (State != RecordingState.Idle)
        {
            return; // Busy with a cycle — ignore.
        }

        State = RecordingState.Recording;
        _audioCapture.Start();
    }

    private void OnReleased(object? sender, EventArgs e)
    {
        if (State == RecordingState.Recording)
        {
            RunCycle();
        }
    }

    // The capture → transcribe → clean → paste cycle. Hotkey release triggers it
    // today; Brick 3b's 60 s auto-stop timer will be a second caller, so the
    // trigger is kept separate from the work. In production the composition root
    // (Brick 14) offloads this to a background thread; the logic here is synchronous.
    private void RunCycle()
    {
        DictationOutcome outcome;
        try
        {
            outcome = ProcessRecording();
        }
        finally
        {
            // Never leave the machine wedged in a non-Idle state: if an adapter
            // throws, the press-guard would otherwise block all future dictation.
            // User-facing error reporting/recovery is Brick 9; this is just the
            // local state-machine invariant.
            State = RecordingState.Idle;
        }

        // Raised only after State is back to Idle, so a handler may legally start
        // a fresh cycle, and after the cycle's work has fully completed.
        Completed?.Invoke(this, outcome);
    }

    private DictationOutcome ProcessRecording()
    {
        State = RecordingState.Transcribing;

        var audio = _audioCapture.Stop();
        if (!audio.HasSpeech)
        {
            return DictationOutcome.NoSpeech;
        }

        var raw = _transcriber.Transcribe(audio.Samples);
        var cleaned = _cleaner.Clean(raw, _settings.FillerRemoval);
        if (cleaned.Length == 0)
        {
            return DictationOutcome.NoSpeech;
        }

        State = RecordingState.Pasting;
        var outcome = _pasteService.Paste(cleaned);
        return outcome == PasteOutcome.LeftOnClipboard
            ? DictationOutcome.LeftOnClipboard
            : DictationOutcome.Pasted;
    }
}
