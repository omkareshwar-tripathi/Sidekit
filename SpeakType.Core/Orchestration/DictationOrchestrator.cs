using SpeakType.Core.Audio;
using SpeakType.Core.Cleanup;
using SpeakType.Core.Input;
using SpeakType.Core.Paste;
using SpeakType.Core.Settings;
using SpeakType.Core.Time;
using SpeakType.Core.Transcription;

namespace SpeakType.Core.Orchestration;

public enum RecordingState { Idle, Recording, Transcribing, Pasting }

/// <summary>Outcome of one dictation cycle, for the UI overlay to surface.</summary>
public enum DictationOutcome { Pasted, LeftOnClipboard, NoSpeech }

/// <summary>
/// State machine that wires the dictation pipeline: hotkey press starts capture,
/// release runs capture → transcribe → clean → paste and reports the outcome.
/// Concurrent hotkey events are ignored while a cycle is in flight (the
/// <see cref="State"/> guard), so each cycle runs to completion. Hold-duration
/// guards discard accidental taps and auto-stop a hold that reaches 60 s.
/// </summary>
public sealed class DictationOrchestrator
{
    // Hold-duration guards (spec Feature 1). Tunable in code.
    private static readonly TimeSpan MinHold = TimeSpan.FromMilliseconds(300);
    private static readonly TimeSpan MaxHold = TimeSpan.FromSeconds(60);

    private readonly IAudioCapture _audioCapture;
    private readonly ITranscriber _transcriber;
    private readonly IPasteService _pasteService;
    private readonly TranscriptCleaner _cleaner;
    private readonly AppSettings _settings;
    private readonly IClock _clock;
    private readonly IAutoStopTimer _autoStopTimer;

    private long _pressTimestamp;

    public DictationOrchestrator(
        IHotkeyListener hotkey,
        IAudioCapture audioCapture,
        ITranscriber transcriber,
        IPasteService pasteService,
        TranscriptCleaner cleaner,
        AppSettings settings,
        IClock clock,
        IAutoStopTimer autoStopTimer)
    {
        ArgumentNullException.ThrowIfNull(hotkey);
        ArgumentNullException.ThrowIfNull(audioCapture);
        ArgumentNullException.ThrowIfNull(transcriber);
        ArgumentNullException.ThrowIfNull(pasteService);
        ArgumentNullException.ThrowIfNull(cleaner);
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(autoStopTimer);

        _audioCapture = audioCapture;
        _transcriber = transcriber;
        _pasteService = pasteService;
        _cleaner = cleaner;
        _settings = settings;
        _clock = clock;
        _autoStopTimer = autoStopTimer;

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
        try
        {
            _pressTimestamp = _clock.GetTimestamp();
            _audioCapture.Start();
            _autoStopTimer.Start(MaxHold, OnAutoStop);
        }
        catch
        {
            // A port threw before recording could begin (e.g. mic in use): reset to
            // Idle so the press-guard doesn't wedge all future dictation. Mirrors the
            // RunCycle finally; user-facing error reporting stays deferred to Brick 9.
            State = RecordingState.Idle;
            throw;
        }
    }

    private void OnReleased(object? sender, EventArgs e)
    {
        if (State != RecordingState.Recording)
        {
            return;
        }

        _autoStopTimer.Cancel();

        if (_clock.GetElapsedTime(_pressTimestamp) < MinHold)
        {
            DiscardRecording(); // accidental tap
            return;
        }

        RunCycle();
    }

    private void OnAutoStop()
    {
        // Timer fired: 60 s reached while still held. Held this long is always past MinHold,
        // so no discard check — just run the cycle. Guarded against a release that raced the
        // timer (a real timer's callback may already be running when Cancel() is called).
        if (State == RecordingState.Recording)
        {
            RunCycle();
        }
    }

    private void DiscardRecording()
    {
        // Accidental tap (< 300 ms): stop capture to keep Start/Stop balanced and release the
        // mic, but throw the audio away — no transcribe, no paste, no Completed outcome.
        try
        {
            _audioCapture.Stop();
        }
        finally
        {
            State = RecordingState.Idle; // never leave the machine wedged if Stop() throws
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
