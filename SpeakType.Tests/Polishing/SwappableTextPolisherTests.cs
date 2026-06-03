using SpeakType.Core.Polishing;

namespace SpeakType.Tests.Polishing;

public sealed class SwappableTextPolisherTests
{
    private sealed class StubPolisher : ITextPolisher
    {
        private readonly string _result;
        public int Disposed { get; private set; }
        public StubPolisher(string result) => _result = result;
        public string Polish(string text) => _result;
    }

    private sealed class DisposableStub : ITextPolisher, IDisposable
    {
        public int Disposed { get; private set; }
        public string Polish(string text) => text.ToUpperInvariant();
        public void Dispose() => Disposed++;
    }

    [Fact]
    public void Passes_text_through_unchanged_when_empty()
    {
        var sut = new SwappableTextPolisher();

        Assert.Equal("hello there", sut.Polish("hello there"));
    }

    [Fact]
    public void Reports_not_active_when_empty_and_active_after_set()
    {
        var sut = new SwappableTextPolisher();
        Assert.False(sut.IsActive);

        sut.Set(new StubPolisher("polished"));

        Assert.True(sut.IsActive);
    }

    [Fact]
    public void Delegates_to_the_inner_polisher_once_set()
    {
        var sut = new SwappableTextPolisher();
        sut.Set(new StubPolisher("He goes to school every day."));

        Assert.Equal("He goes to school every day.", sut.Polish("he go to school every days"));
    }

    [Fact]
    public void Set_disposes_the_replaced_inner()
    {
        var first = new DisposableStub();
        var second = new DisposableStub();
        var sut = new SwappableTextPolisher();
        sut.Set(first);

        sut.Set(second);

        Assert.Equal(1, first.Disposed);
        Assert.Equal(0, second.Disposed);
    }

    [Fact]
    public void Setting_the_same_inner_is_a_noop_and_does_not_dispose_it()
    {
        var inner = new DisposableStub();
        var sut = new SwappableTextPolisher();
        sut.Set(inner);

        sut.Set(inner);

        Assert.Equal(0, inner.Disposed);
        Assert.True(sut.IsActive);
    }

    [Fact]
    public void Dispose_disposes_the_current_inner()
    {
        var inner = new DisposableStub();
        var sut = new SwappableTextPolisher();
        sut.Set(inner);

        sut.Dispose();

        Assert.Equal(1, inner.Disposed);
    }

    [Fact]
    public void Set_null_clears_back_to_passthrough()
    {
        var sut = new SwappableTextPolisher();
        sut.Set(new StubPolisher("polished"));

        sut.Set(null);

        Assert.False(sut.IsActive);
        Assert.Equal("raw", sut.Polish("raw"));
    }
}
