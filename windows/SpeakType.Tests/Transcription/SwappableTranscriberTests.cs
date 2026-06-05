using System;
using SpeakType.Core.Transcription;

namespace SpeakType.Tests.Transcription;

public sealed class SwappableTranscriberTests
{
    private sealed class FakeTranscriber : ITranscriber, IDisposable
    {
        public string Result { get; init; } = "";
        public float[]? ReceivedSamples { get; private set; }
        public bool Disposed { get; private set; }
        public string Transcribe(float[] samples) { ReceivedSamples = samples; return Result; }
        public void Dispose() => Disposed = true;
    }

    [Fact]
    public void Transcribe_delegates_to_the_current_inner()
    {
        var inner = new FakeTranscriber { Result = "hello" };
        var sut = new SwappableTranscriber(inner);
        var samples = new float[] { 1f, 2f, 3f };

        Assert.Equal("hello", sut.Transcribe(samples));
        Assert.Same(samples, inner.ReceivedSamples);
    }

    [Fact]
    public void Swap_routes_subsequent_transcribe_to_the_new_inner()
    {
        var a = new FakeTranscriber { Result = "a" };
        var b = new FakeTranscriber { Result = "b" };
        var sut = new SwappableTranscriber(a);

        sut.Swap(b);

        Assert.Equal("b", sut.Transcribe(Array.Empty<float>()));
    }

    [Fact]
    public void Swap_disposes_the_replaced_inner()
    {
        var a = new FakeTranscriber { Result = "a" };
        var b = new FakeTranscriber { Result = "b" };
        var sut = new SwappableTranscriber(a);

        sut.Swap(b);

        Assert.True(a.Disposed);
        Assert.False(b.Disposed);
    }

    [Fact]
    public void Swap_to_the_same_inner_is_a_noop_and_does_not_dispose_it()
    {
        var a = new FakeTranscriber { Result = "a" };
        var sut = new SwappableTranscriber(a);

        sut.Swap(a);

        Assert.False(a.Disposed);
        Assert.Equal("a", sut.Transcribe(Array.Empty<float>()));
    }

    [Fact]
    public void Dispose_disposes_the_current_inner()
    {
        var a = new FakeTranscriber { Result = "a" };
        var sut = new SwappableTranscriber(a);

        sut.Dispose();

        Assert.True(a.Disposed);
    }

    [Fact]
    public void Constructor_throws_on_null_inner()
    {
        Assert.Throws<ArgumentNullException>(() => new SwappableTranscriber(null!));
    }

    [Fact]
    public void Swap_throws_on_null_inner()
    {
        var sut = new SwappableTranscriber(new FakeTranscriber());
        Assert.Throws<ArgumentNullException>(() => sut.Swap(null!));
    }
}
