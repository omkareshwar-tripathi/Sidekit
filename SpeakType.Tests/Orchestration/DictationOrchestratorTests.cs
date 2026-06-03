using SpeakType.Core.Audio;
using SpeakType.Core.Cleanup;
using SpeakType.Core.Correction;
using SpeakType.Core.Logging;
using SpeakType.Core.Orchestration;
using SpeakType.Core.Paste;
using SpeakType.Core.Settings;
using SpeakType.Core.Time;

namespace SpeakType.Tests.Orchestration;

public sealed class DictationOrchestratorTests
{
    private readonly FakeHotkeyListener _hotkey = new();
    private readonly FakeAudioCapture _audio = new();
    private readonly FakeTranscriber _transcriber = new();
    private readonly FakePasteService _paste = new();
    private readonly FakeClock _clock = new();
    private readonly FakeAutoStopTimer _timer = new();
    private readonly DictationOrchestrator _sut;

    private readonly List<DictationOutcome> _outcomes = new();

    public DictationOrchestratorTests()
    {
        _sut = new DictationOrchestrator(
            _hotkey, _audio, _transcriber, _paste, new TranscriptCleaner(), new AppSettings(),
            _clock, _timer);
        _sut.Completed += (_, outcome) => _outcomes.Add(outcome);
    }

    [Fact]
    public void Normal_flow_cleans_pastes_and_reports_pasted()
    {
        var samples = new[] { 0.1f, 0.2f };
        _audio.Result = new CapturedAudio(samples, HasSpeech: true);
        _transcriber.Result = "Um, hello.";

        _hotkey.Press();
        _hotkey.Release();

        Assert.Same(samples, _transcriber.ReceivedSamples); // captured audio reached the transcriber
        Assert.Equal("Hello. ", _paste.ReceivedText);       // and the cleaned text reached paste
        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Press_enters_recording_state()
    {
        _hotkey.Press();

        Assert.Equal(RecordingState.Recording, _sut.State);
        Assert.Equal(1, _audio.StartCount);
    }

    [Fact]
    public void Second_press_while_recording_is_ignored()
    {
        _hotkey.Press();
        _hotkey.Press();

        Assert.Equal(1, _audio.StartCount);

        _hotkey.Release();

        Assert.Single(_outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Silent_audio_skips_transcription_and_paste()
    {
        _audio.Result = new CapturedAudio(new[] { 0.0f }, HasSpeech: false);

        _hotkey.Press();
        _hotkey.Release();

        Assert.False(_transcriber.WasCalled);
        Assert.Equal(0, _paste.CallCount);
        Assert.Equal(new[] { DictationOutcome.NoSpeech }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void No_editable_target_reports_left_on_clipboard()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello there.";
        _paste.Result = PasteOutcome.LeftOnClipboard;

        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal(new[] { DictationOutcome.LeftOnClipboard }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Empty_after_cleaning_skips_paste()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "[BLANK_AUDIO]";

        _hotkey.Press();
        _hotkey.Release();

        Assert.True(_transcriber.WasCalled); // distinguishes this path from the silence-skip path
        Assert.Equal(0, _paste.CallCount);
        Assert.Equal(new[] { DictationOutcome.NoSpeech }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Release_without_press_is_ignored()
    {
        _hotkey.Release();

        Assert.Empty(_outcomes);
        Assert.Equal(0, _audio.StartCount);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Second_release_after_cycle_is_ignored()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello there.";

        _hotkey.Press();
        _hotkey.Release();
        _hotkey.Release(); // stray key-up / auto-repeat jitter after the cycle finished

        Assert.Single(_outcomes);
        Assert.Equal(1, _paste.CallCount);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Adapter_throwing_resets_state_so_the_next_cycle_works()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.ThrowOnCall = new InvalidOperationException("transcription failed");

        _hotkey.Press();
        Assert.Throws<InvalidOperationException>(() => _hotkey.Release());

        // The throw must NOT wedge the machine: State is back to Idle and no outcome fired.
        Assert.Equal(RecordingState.Idle, _sut.State);
        Assert.Empty(_outcomes);

        // A subsequent dictation succeeds normally.
        _transcriber.ThrowOnCall = null;
        _transcriber.Result = "Hello again.";
        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal("Hello again. ", _paste.ReceivedText);
        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Hold_under_300ms_is_discarded()
    {
        _clock.Elapsed = TimeSpan.FromMilliseconds(100);
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";

        _hotkey.Press();
        _hotkey.Release();

        Assert.False(_transcriber.WasCalled);
        Assert.Equal(0, _paste.CallCount);
        Assert.Empty(_outcomes); // accidental tap produces no Completed outcome
        Assert.Equal(RecordingState.Idle, _sut.State);
        Assert.Equal(1, _audio.StopCount); // capture was stopped to release the mic
        Assert.Equal(1, _timer.CancelCount);
    }

    [Fact]
    public void Auto_stop_runs_the_cycle_while_still_held()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";

        _hotkey.Press();
        _timer.Fire(); // 60 s reached, still held

        Assert.True(_transcriber.WasCalled);
        Assert.Equal(1, _paste.CallCount);
        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);

        _hotkey.Release(); // user finally lets go — ignored, cycle already ran

        Assert.Single(_outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Auto_stop_timer_starts_at_60s_and_is_cancelled_on_release()
    {
        _hotkey.Press();

        Assert.True(_timer.IsRunning);
        Assert.Equal(TimeSpan.FromSeconds(60), _timer.Delay);

        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";
        _hotkey.Release();

        Assert.Equal(1, _timer.CancelCount);
        Assert.False(_timer.IsRunning);
    }

    [Fact]
    public void Discard_resets_state_so_the_next_cycle_works()
    {
        _clock.Elapsed = TimeSpan.FromMilliseconds(50);
        _hotkey.Press();
        _hotkey.Release(); // discarded

        _clock.Elapsed = TimeSpan.FromSeconds(1);
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hi.";
        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Audio_start_throwing_resets_state_so_the_next_press_works()
    {
        _audio.ThrowOnStart = new InvalidOperationException("mic in use");

        Assert.Throws<InvalidOperationException>(() => _hotkey.Press());

        // The throw on press must NOT wedge the machine in Recording.
        Assert.Equal(RecordingState.Idle, _sut.State);
        Assert.Empty(_outcomes);

        // A subsequent press/release dictates normally.
        _audio.ThrowOnStart = null;
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello again.";
        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal("Hello again. ", _paste.ReceivedText);
        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Cycle_is_run_through_the_injected_dispatcher()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Hello." };
        var paste = new FakePasteService();
        var clock = new FakeClock();
        var timer = new FakeAutoStopTimer();
        var dispatcher = new DeferredDispatcher();
        var outcomes = new List<DictationOutcome>();
        var sut = new DictationOrchestrator(
            hotkey, audio, transcriber, paste, new TranscriptCleaner(), new AppSettings(),
            clock, timer, dispatcher);
        sut.Completed += (_, o) => outcomes.Add(o);

        hotkey.Press();
        hotkey.Release();

        // The cycle was handed to the dispatcher, not run inline.
        Assert.Equal(1, dispatcher.DispatchCount);
        Assert.Empty(outcomes);
        Assert.Equal(RecordingState.Transcribing, sut.State); // claimed, not yet finished
        Assert.Equal(0, paste.CallCount);

        dispatcher.RunPending();

        Assert.Equal(new[] { DictationOutcome.Pasted }, outcomes);
        Assert.Equal(1, paste.CallCount);
        Assert.Equal(RecordingState.Idle, sut.State);
    }

    [Fact]
    public void Auto_stop_claim_blocks_a_following_release_from_running_a_second_cycle()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Hello." };
        var paste = new FakePasteService();
        var clock = new FakeClock();
        var timer = new FakeAutoStopTimer();
        var dispatcher = new DeferredDispatcher();
        var outcomes = new List<DictationOutcome>();
        var sut = new DictationOrchestrator(
            hotkey, audio, transcriber, paste, new TranscriptCleaner(), new AppSettings(),
            clock, timer, dispatcher);
        sut.Completed += (_, o) => outcomes.Add(o);

        hotkey.Press();
        timer.Fire(); // auto-stop claims the cycle and defers it

        Assert.Equal(1, dispatcher.DispatchCount);
        Assert.Equal(RecordingState.Transcribing, sut.State);

        hotkey.Release(); // claim already taken — must not dispatch a second cycle

        Assert.Equal(1, dispatcher.DispatchCount);

        dispatcher.RunPending();

        Assert.Equal(new[] { DictationOutcome.Pasted }, outcomes);
        Assert.Equal(1, paste.CallCount);
        Assert.Equal(RecordingState.Idle, sut.State);
    }

    [Fact]
    public void State_changed_reports_full_lifecycle_on_a_normal_cycle()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";

        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal(
            new[]
            {
                RecordingState.Recording, RecordingState.Transcribing,
                RecordingState.Pasting, RecordingState.Idle,
            },
            states);
    }

    [Fact]
    public void State_changed_skips_pasting_when_no_speech()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);
        _audio.Result = new CapturedAudio(new[] { 0.0f }, HasSpeech: false);

        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal(
            new[] { RecordingState.Recording, RecordingState.Transcribing, RecordingState.Idle },
            states);
    }

    [Fact]
    public void State_changed_on_a_tap_is_recording_then_idle_only()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);
        _clock.Elapsed = TimeSpan.FromMilliseconds(100);

        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal(new[] { RecordingState.Recording, RecordingState.Idle }, states);
    }

    [Fact]
    public void State_changed_reports_full_lifecycle_on_auto_stop()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";

        _hotkey.Press();
        _timer.Fire();

        Assert.Equal(
            new[]
            {
                RecordingState.Recording, RecordingState.Transcribing,
                RecordingState.Pasting, RecordingState.Idle,
            },
            states);
    }

    [Fact]
    public void Cancel_while_recording_returns_to_idle_and_discards()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);

        _hotkey.Press();
        _sut.Cancel();

        Assert.Equal(RecordingState.Idle, _sut.State);
        Assert.Equal(1, _audio.StopCount); // capture stopped to release the mic
        Assert.Equal(new[] { RecordingState.Recording, RecordingState.Idle }, states);
        Assert.Empty(_outcomes); // no Completed on a cancel
        Assert.False(_transcriber.WasCalled);
    }

    [Fact]
    public void Cancel_keeps_the_cycle_claimed_while_stopping_capture()
    {
        // Regression: Cancel must keep _state non-Idle across Stop(), so a concurrent press on the
        // still-live hook (after a rebind) can't pass OnPressed's Idle guard and Start() a capture
        // that overlaps this Stop() — NAudioCapture requires Start/Stop never overlap.
        var stateDuringStop = RecordingState.Idle;
        _audio.OnStop = () => stateDuringStop = _sut.State;

        _hotkey.Press();
        _sut.Cancel();

        Assert.NotEqual(RecordingState.Idle, stateDuringStop); // claimed during Stop → a racing Start() is blocked
        Assert.Equal(RecordingState.Idle, _sut.State);         // and reset to Idle afterward
    }

    [Fact]
    public void Cancel_when_idle_is_a_noop()
    {
        var states = new List<RecordingState>();
        _sut.StateChanged += (_, s) => states.Add(s);

        _sut.Cancel();

        Assert.Empty(states);
        Assert.Equal(0, _audio.StopCount);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Cancel_during_active_cycle_is_ignored()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Hello." };
        var paste = new FakePasteService();
        var clock = new FakeClock();
        var timer = new FakeAutoStopTimer();
        var dispatcher = new DeferredDispatcher();
        var outcomes = new List<DictationOutcome>();
        var sut = new DictationOrchestrator(
            hotkey, audio, transcriber, paste, new TranscriptCleaner(), new AppSettings(),
            clock, timer, dispatcher);
        sut.Completed += (_, o) => outcomes.Add(o);

        hotkey.Press();
        hotkey.Release(); // claims Transcribing, cycle queued but not run

        Assert.Equal(RecordingState.Transcribing, sut.State);

        sut.Cancel(); // a cycle is in flight — must be ignored

        Assert.Equal(RecordingState.Transcribing, sut.State);
        Assert.Equal(0, audio.StopCount); // not double-stopped (cycle's Stop runs when it runs)

        dispatcher.RunPending();

        Assert.Equal(new[] { DictationOutcome.Pasted }, outcomes);
        Assert.Equal(RecordingState.Idle, sut.State);
    }

    [Fact]
    public void Cancel_then_new_cycle_still_works()
    {
        _audio.Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true);
        _transcriber.Result = "Hello.";

        _hotkey.Press();
        _sut.Cancel();

        // The cancel must not wedge the state machine: a fresh cycle dictates normally.
        _hotkey.Press();
        _hotkey.Release();

        Assert.Equal("Hello. ", _paste.ReceivedText);
        Assert.Equal(new[] { DictationOutcome.Pasted }, _outcomes);
        Assert.Equal(RecordingState.Idle, _sut.State);
    }

    [Fact]
    public void Logs_recording_transcribe_transcript_and_latency_on_a_normal_cycle()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Um, hello." };
        var sink = new FakeLogSink();
        var logger = new AppLogger(sink, () => true);
        _ = new DictationOrchestrator(
            hotkey, audio, transcriber, new FakePasteService(), new TranscriptCleaner(), new AppSettings(),
            new FakeClock(), new FakeAutoStopTimer(), dispatcher: null, logger: logger);

        hotkey.Press();
        hotkey.Release();

        Assert.Equal(
            new[]
            {
                "recording 1.0s", "transcribe 1.0s, 7 chars", "transcript: Hello. ", "latency 1.0s",
            },
            sink.Lines);
    }

    [Fact]
    public void Transcript_is_omitted_when_debug_logging_is_disabled()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Um, hello." };
        var sink = new FakeLogSink();
        var logger = new AppLogger(sink, () => false);
        _ = new DictationOrchestrator(
            hotkey, audio, transcriber, new FakePasteService(), new TranscriptCleaner(), new AppSettings(),
            new FakeClock(), new FakeAutoStopTimer(), dispatcher: null, logger: logger);

        hotkey.Press();
        hotkey.Release();

        Assert.DoesNotContain(sink.Lines, line => line.StartsWith("transcript:", StringComparison.Ordinal));
        Assert.Contains("recording 1.0s", sink.Lines);
        Assert.Contains("transcribe 1.0s, 7 chars", sink.Lines);
        Assert.Contains("latency 1.0s", sink.Lines);
    }

    [Fact]
    public void Logs_error_when_an_adapter_throws()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber
        {
            ThrowOnCall = new InvalidOperationException("boom"),
        };
        var sink = new FakeLogSink();
        var logger = new AppLogger(sink, () => true);
        _ = new DictationOrchestrator(
            hotkey, audio, transcriber, new FakePasteService(), new TranscriptCleaner(), new AppSettings(),
            new FakeClock(), new FakeAutoStopTimer(), dispatcher: null, logger: logger);

        hotkey.Press();
        Assert.Throws<InvalidOperationException>(() => hotkey.Release());

        Assert.Contains("recording 1.0s", sink.Lines);
        Assert.Contains("error: boom", sink.Lines);
    }

    [Fact]
    public void Silent_audio_logs_only_recording()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.0f }, HasSpeech: false) };
        var sink = new FakeLogSink();
        var logger = new AppLogger(sink, () => true);
        _ = new DictationOrchestrator(
            hotkey, audio, new FakeTranscriber(), new FakePasteService(), new TranscriptCleaner(),
            new AppSettings(), new FakeClock(), new FakeAutoStopTimer(), dispatcher: null, logger: logger);

        hotkey.Press();
        hotkey.Release();

        Assert.Equal(new[] { "recording 1.0s" }, sink.Lines);
    }

    [Fact]
    public void Correction_pipeline_runs_between_clean_and_paste()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Um, hello." };
        var paste = new FakePasteService();
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (new UpperCorrector(), s => s.SpellCorrection),
        });
        var settings = new AppSettings { FillerRemoval = true, SpellCorrection = true };
        var sut = new DictationOrchestrator(
            hotkey, audio, transcriber, paste, new TranscriptCleaner(), settings,
            new FakeClock(), new FakeAutoStopTimer(), correctionPipeline: pipeline);

        hotkey.Press();
        hotkey.Release();

        // Cleaner ⇒ "Hello. " ; pipeline uppercases ⇒ "HELLO. "
        Assert.Equal("HELLO. ", paste.ReceivedText);
    }

    [Fact]
    public void Correction_pipeline_skipped_when_setting_off()
    {
        var hotkey = new FakeHotkeyListener();
        var audio = new FakeAudioCapture { Result = new CapturedAudio(new[] { 0.1f }, HasSpeech: true) };
        var transcriber = new FakeTranscriber { Result = "Um, hello." };
        var paste = new FakePasteService();
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (new UpperCorrector(), s => s.SpellCorrection),
        });
        var settings = new AppSettings { SpellCorrection = false };
        var sut = new DictationOrchestrator(
            hotkey, audio, transcriber, paste, new TranscriptCleaner(), settings,
            new FakeClock(), new FakeAutoStopTimer(), correctionPipeline: pipeline);

        hotkey.Press();
        hotkey.Release();

        Assert.Equal("Hello. ", paste.ReceivedText); // unchanged by the (disabled) stage
    }

    private sealed class UpperCorrector : ITextCorrector
    {
        public string Correct(string text) => text.ToUpperInvariant();
    }
}
