using Sidekit.Core.Orchestration;

namespace Sidekit.Tests.Orchestration;

public sealed class TrayStateTests
{
    [Theory]
    [InlineData(RecordingState.Idle, TrayState.Idle)]
    [InlineData(RecordingState.Recording, TrayState.Recording)]
    [InlineData(RecordingState.Transcribing, TrayState.Busy)]
    [InlineData(RecordingState.Pasting, TrayState.Busy)]
    public void From_maps_recording_state_to_tray_state(RecordingState state, TrayState expected)
    {
        Assert.Equal(expected, TrayStatus.From(state));
    }
}
