using SpeakType.Core.Audio;
using SpeakType.Core.Input;
using SpeakType.Core.Paste;
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
    public CapturedAudio Result { get; set; } = new(Array.Empty<float>(), HasSpeech: true);

    public void Start() => StartCount++;

    public CapturedAudio Stop() => Result;
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
