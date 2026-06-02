using SpeakType.Core.Audio;
using SpeakType.Core.Input;
using SpeakType.Core.Logging;
using SpeakType.Core.Orchestration;
using SpeakType.Core.Paste;
using SpeakType.Core.Time;
using SpeakType.Core.Transcription;

namespace SpeakType.Tests.Orchestration;

/// <summary>Drives the orchestrator's hotkey events from the tests.</summary>
internal sealed class FakeHotkeyListener : IHotkeyListener
{
    public event EventHandler? Pressed;
    public event EventHandler? Released;

    public void Press() => Pressed?.Invoke(this, EventArgs.Empty);
    public void Release() => Released?.Invoke(this, EventArgs.Empty);
}

internal sealed class FakeAudioCapture : IAudioCapture
{
    public int StartCount { get; private set; }
    public int StopCount { get; private set; }
    public CapturedAudio Result { get; set; } = new(Array.Empty<float>(), HasSpeech: true);

    /// <summary>When set, <see cref="Start"/> throws it (simulates a mic that won't open).</summary>
    public Exception? ThrowOnStart { get; set; }

    public void Start()
    {
        StartCount++;
        if (ThrowOnStart is not null)
        {
            throw ThrowOnStart;
        }
    }

    public CapturedAudio Stop()
    {
        StopCount++;
        return Result;
    }
}

internal sealed class FakeTranscriber : ITranscriber
{
    public bool WasCalled { get; private set; }
    public float[]? ReceivedSamples { get; private set; }
    public string Result { get; set; } = "";

    /// <summary>When set, <see cref="Transcribe"/> throws it (simulates an adapter failure).</summary>
    public Exception? ThrowOnCall { get; set; }

    public string Transcribe(float[] samples)
    {
        WasCalled = true;
        ReceivedSamples = samples;
        if (ThrowOnCall is not null)
        {
            throw ThrowOnCall;
        }

        return Result;
    }
}

internal sealed class FakePasteService : IPasteService
{
    public int CallCount { get; private set; }
    public string? ReceivedText { get; private set; }
    public PasteOutcome Result { get; set; } = PasteOutcome.Pasted;

    public PasteOutcome Paste(string text)
    {
        CallCount++;
        ReceivedText = text;
        return Result;
    }
}

/// <summary>
/// Controllable clock. <see cref="Elapsed"/> is what the orchestrator sees for the
/// press→release hold; it defaults to a normal hold (past the 300 ms guard) so existing
/// flow tests are unaffected. Discard tests set it below the guard.
/// </summary>
internal sealed class FakeClock : IClock
{
    public TimeSpan Elapsed { get; set; } = TimeSpan.FromSeconds(1);

    public long GetTimestamp() => 0;

    public TimeSpan GetElapsedTime(long startingTimestamp) => Elapsed;
}

/// <summary>One-shot timer fake. Tests inspect Start/Cancel and fire it on demand.</summary>
internal sealed class FakeAutoStopTimer : IAutoStopTimer
{
    public bool IsRunning { get; private set; }
    public TimeSpan Delay { get; private set; }
    public int CancelCount { get; private set; }

    private Action? _onElapsed;

    public void Start(TimeSpan delay, Action onElapsed)
    {
        IsRunning = true;
        Delay = delay;
        _onElapsed = onElapsed;
    }

    public void Cancel()
    {
        if (IsRunning)
        {
            CancelCount++;
        }

        IsRunning = false;
        _onElapsed = null;
    }

    /// <summary>Simulate the timer elapsing.</summary>
    public void Fire()
    {
        var callback = _onElapsed;
        IsRunning = false;
        _onElapsed = null;
        callback?.Invoke();
    }
}

/// <summary>Captures the cycle action instead of running it, so a test can run it on demand
/// and interleave a second trigger in between (to exercise the atomic claim deterministically).</summary>
internal sealed class DeferredDispatcher : ICycleDispatcher
{
    private Action? _pending;

    public int DispatchCount { get; private set; }

    public void Run(Action cycle)
    {
        DispatchCount++;
        _pending = cycle;
    }

    /// <summary>Run the most recently captured cycle, if any.</summary>
    public void RunPending()
    {
        var work = _pending;
        _pending = null;
        work?.Invoke();
    }
}

/// <summary>Captures the formatted log lines so a test can assert what AppLogger emitted.</summary>
internal sealed class FakeLogSink : ILogSink
{
    public List<string> Lines { get; } = new();

    public void Write(string message) => Lines.Add(message);
}
