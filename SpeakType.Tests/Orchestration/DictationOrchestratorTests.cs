using SpeakType.Core.Audio;
using SpeakType.Core.Cleanup;
using SpeakType.Core.Orchestration;
using SpeakType.Core.Paste;
using SpeakType.Core.Settings;

namespace SpeakType.Tests.Orchestration;

public sealed class DictationOrchestratorTests
{
    private readonly FakeHotkeyListener _hotkey = new();
    private readonly FakeAudioCapture _audio = new();
    private readonly FakeTranscriber _transcriber = new();
    private readonly FakePasteService _paste = new();
    private readonly DictationOrchestrator _sut;

    private readonly List<DictationOutcome> _outcomes = new();

    public DictationOrchestratorTests()
    {
        _sut = new DictationOrchestrator(
            _hotkey, _audio, _transcriber, _paste, new TranscriptCleaner(), new AppSettings());
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
}
