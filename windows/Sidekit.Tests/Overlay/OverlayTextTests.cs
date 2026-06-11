using Sidekit.Core.Overlay;

namespace Sidekit.Tests.Overlay;

public sealed class OverlayTextTests
{
    [Theory]
    [InlineData(OverlayStatus.Listening, "🎙 Listening…")]
    [InlineData(OverlayStatus.Transcribing, "⚙ Transcribing…")]
    [InlineData(OverlayStatus.NoSpeech, "No speech detected")]
    [InlineData(OverlayStatus.CopiedManually, "Copied — paste manually")]
    public void For_maps_status_to_text(OverlayStatus status, string expected)
    {
        Assert.Equal(expected, OverlayText.For(status));
    }
}
