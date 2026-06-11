using Sidekit.Core.Audio;
using Sidekit.Core.Cleanup;
using Sidekit.Core.Input;
using Sidekit.Core.Logging;
using Sidekit.Core.Paste;
using Sidekit.Core.Settings;
using Sidekit.Core.Time;
using Sidekit.Core.Transcription;

namespace Sidekit.Core.Orchestration;

public enum RecordingState { Idle, Recording, Transcribing, Pasting }

/// <summary>Outcome of one dictation cycle, for the UI overlay to surface.</summary>
public enum DictationOutcome { Pasted, LeftOnClipboard, NoSpeech }

/// <summary>
/// State machine that wires the dictation pipeline: hotkey press starts capture,
/// release runs capture → transcribe → clean → paste and reports the outcome.
/// Concurrent hotkey events are ignored while a cycle is in flight (the
/// <see cref="State"/> guard), so each cycle runs to completion. Hold-duration
/// guards discard accidental taps and auto-stop a hold that reaches 60 s.
/// All <see cref="State"/> access is serialized by an internal lock, so the hotkey
/// thread, the thread-pool auto-stop callback, and the background cycle dispatcher
/// can drive it concurrently without racing.
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
    private readonly ICycleDispatcher _dispatcher;
    private readonly AppLogger? _logger;
    private readonly object _gate = new();

    private RecordingState _state = RecordingState.Idle;
    private long _pressTimestamp;
    private TimeSpan _recordingDuration;
    private long _releaseTimestamp;

    public DictationOrchestrator(
        IHotkeyListener hotkey,
        IAudioCapture audioCapture,
        ITranscriber transcriber,
        IPasteService pasteService,
        TranscriptCleaner cleaner,
        AppSettings settings,
        IClock clock,
        IAutoStopTimer autoStopTimer,
        ICycleDispatcher? dispatcher = null,
        AppLogger? logger = null)
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
        _dispatcher = dispatcher ?? new SynchronousCycleDispatcher();
        _logger = logger;

        hotkey.Pressed += OnPressed;
        hotkey.Released += OnReleased;
    }

    /// <summary>The current pipeline state. Read under the lock so a caller on another thread
    /// (e.g. the UI reading it while the background cycle runs) observes the latest write.</summary>
    public RecordingState State
    {
        get { lock (_gate) { return _state; } }
    }

    /// <summary>Raised once at the end of every dictation cycle that produced an outcome.</summary>
    public event EventHandler<DictationOutcome>? Completed;

    /// <summary>Raised after each UI-meaningful lifecycle transition: <see cref="RecordingState.Recording"/>
    /// on press, <see cref="RecordingState.Transcribing"/> when a cycle actually begins processing,
    /// <see cref="RecordingState.Pasting"/> while text is pasted, and <see cref="RecordingState.Idle"/>
    /// when the cycle finishes or an accidental tap is discarded. The transient Transcribing state an
    /// accidental tap passes through (claim then discard) is NOT surfaced. Raised outside the lock (like
    /// <see cref="Completed"/>), so a handler may be slow or marshal to another thread.</summary>
    public event EventHandler<RecordingState>? StateChanged;

    private void RaiseStateChanged(RecordingState state) => StateChanged?.Invoke(this, state);

    // Atomically transition Recording -> Transcribing. Returns true to the single caller that wins
    // the claim; a racing release/auto-stop sees a non-Recording state and gets false. This is what
    // stops a key-release and the 60 s auto-stop from both running the cycle.
    private bool TryClaimForProcessing()
    {
        lock (_gate)
        {
            if (_state != RecordingState.Recording)
            {
                return false;
            }

            _state = RecordingState.Transcribing;
            return true;
        }
    }

    private void OnPressed(object? sender, EventArgs e)
    {
        // Establishing a recording — stamping the press time, opening the mic, arming the auto-stop
        // timer — all happens under the lock, and State becomes Recording only once they succeed. So a
        // release/auto-stop on another thread never sees Recording before the capture exists, and never
        // runs a cycle against an un-started capture.
        lock (_gate)
        {
            if (_state != RecordingState.Idle)
            {
                return; // Busy with a cycle — ignore.
            }

            try
            {
                _pressTimestamp = _clock.GetTimestamp();
                _audioCapture.Start();
                _autoStopTimer.Start(MaxHold, OnAutoStop);
                _state = RecordingState.Recording;
            }
            catch
            {
                // A port threw before recording could begin (e.g. mic in use): stay Idle so the
                // press-guard doesn't wedge all future dictation. User-facing error reporting is Brick 9.
                _state = RecordingState.Idle;
                throw;
            }
        }

        RaiseStateChanged(RecordingState.Recording);
    }

    // Commit to running a cycle: stamp the release time (for latency), announce Transcribing, and hand
    // the cycle to the dispatcher. The fields read by RunCycle on the (possibly background) cycle thread
    // are written here first; the dispatcher's Task.Run establishes the happens-before for that read.
    private void StartCycle()
    {
        _releaseTimestamp = _clock.GetTimestamp();
        RaiseStateChanged(RecordingState.Transcribing);
        _dispatcher.Run(RunCycle);
    }

    private void OnReleased(object? sender, EventArgs e)
    {
        _autoStopTimer.Cancel();

        if (!TryClaimForProcessing())
        {
            return; // not recording, or the auto-stop already claimed this cycle
        }

        // Reading _pressTimestamp unlocked is safe here: the claim above acquired the lock, so this
        // thread has already synchronized with OnPressed's write of it.
        var hold = _clock.GetElapsedTime(_pressTimestamp);
        if (hold < MinHold)
        {
            DiscardRecording(); // accidental tap
            return;
        }

        _recordingDuration = hold;
        StartCycle();
    }

    private void OnAutoStop()
    {
        // Timer fired: 60 s reached while still held. Guarded by the atomic claim so a release that
        // raced the timer can't also run the cycle.
        if (TryClaimForProcessing())
        {
            _recordingDuration = _clock.GetElapsedTime(_pressTimestamp);
            StartCycle();
        }
    }

    /// <summary>
    /// Cancels an in-progress recording and returns to <see cref="RecordingState.Idle"/>, discarding
    /// the captured audio (no transcribe, no paste, no <see cref="Completed"/>). Intended for when a
    /// pause or hotkey-rebind happens mid-hold — the hook won't fire <see cref="OnReleased"/> for that
    /// press, so the consumer calls this to avoid a stuck Recording state. A no-op unless currently
    /// Recording (the same atomic claim used by release/auto-stop), so it never interrupts a running
    /// cycle. Raises <see cref="StateChanged"/>(Idle) on the success path, outside the lock.
    /// </summary>
    public void Cancel()
    {
        // Claim the cycle the same way release/auto-stop do, but to a transient non-Idle state we
        // never surface. Keeping _state non-Idle while we Stop() the capture blocks a concurrent
        // OnPressed (a fresh press on the still-live hook right after a rebind) from calling Start()
        // and overlapping our Stop() — NAudioCapture requires Start/Stop never overlap. Reset to Idle
        // in the finally (so a throwing Stop() can't wedge the machine), and surface only Idle.
        lock (_gate)
        {
            if (_state != RecordingState.Recording)
            {
                return;
            }

            _state = RecordingState.Transcribing;
        }

        _autoStopTimer.Cancel();
        try
        {
            _audioCapture.Stop(); // discard the audio
        }
        finally
        {
            lock (_gate)
            {
                _state = RecordingState.Idle;
            }
        }

        RaiseStateChanged(RecordingState.Idle);
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
            lock (_gate)
            {
                _state = RecordingState.Idle; // never leave the machine wedged if Stop() throws
            }
        }

        // Outside the finally so a throwing StateChanged handler can't mask a Stop() failure.
        RaiseStateChanged(RecordingState.Idle);
    }

    // The capture → transcribe → clean → paste cycle. Both hotkey release and the 60 s auto-stop
    // are callers, each after winning the atomic claim, so the trigger is kept separate from the
    // work. In production the composition root offloads this to a background thread via the injected
    // dispatcher; by default it runs synchronously.
    private void RunCycle()
    {
        _logger?.Recording(_recordingDuration);

        DictationOutcome outcome;
        try
        {
            outcome = ProcessRecording();
        }
        catch (Exception ex)
        {
            _logger?.Error(ex.Message);
            throw;
        }
        finally
        {
            // Never leave the machine wedged in a non-Idle state: if an adapter
            // throws, the press-guard would otherwise block all future dictation.
            // User-facing error reporting/recovery is Brick 9; this is just the
            // local state-machine invariant.
            lock (_gate)
            {
                _state = RecordingState.Idle;
            }
        }

        // Raised on the success path only (a rethrow skips this) and outside the finally, so a
        // throwing StateChanged handler can't mask the adapter exception. On the error path the
        // dispatcher's onError owns the UI reset. Both fire after State is Idle, so a handler may
        // legally start a fresh cycle, and after the cycle's work has fully completed.
        RaiseStateChanged(RecordingState.Idle);
        Completed?.Invoke(this, outcome);
    }

    private DictationOutcome ProcessRecording()
    {
        var audio = _audioCapture.Stop();
        if (!audio.HasSpeech)
        {
            return DictationOutcome.NoSpeech;
        }

        var t0 = _clock.GetTimestamp();
        var raw = _transcriber.Transcribe(audio.Samples);
        var transcribeDuration = _clock.GetElapsedTime(t0);
        var cleaned = _cleaner.Clean(raw, _settings.FillerRemoval);
        _logger?.Transcribed(transcribeDuration, cleaned.Length);
        if (cleaned.Length == 0)
        {
            return DictationOutcome.NoSpeech;
        }

        _logger?.Transcript(cleaned);

        lock (_gate)
        {
            _state = RecordingState.Pasting;
        }

        RaiseStateChanged(RecordingState.Pasting);

        var outcome = _pasteService.Paste(cleaned);
        _logger?.Latency(_clock.GetElapsedTime(_releaseTimestamp));
        return outcome == PasteOutcome.LeftOnClipboard
            ? DictationOutcome.LeftOnClipboard
            : DictationOutcome.Pasted;
    }
}
