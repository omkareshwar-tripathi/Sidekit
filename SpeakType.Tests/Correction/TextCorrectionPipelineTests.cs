using SpeakType.Core.Correction;
using SpeakType.Core.Settings;

namespace SpeakType.Tests.Correction;

public sealed class TextCorrectionPipelineTests
{
    // Minimal fake stage: appends a marker so order/invocation is observable.
    private static ITextCorrector Appender(string marker) =>
        new DelegateCorrector(text => text + marker);

    private sealed class DelegateCorrector(Func<string, string> f) : ITextCorrector
    {
        public string Correct(string text) => f(text);
    }

    [Fact]
    public void Runs_stages_in_order()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), _ => true),
            (Appender("B"), _ => true),
        });

        Assert.Equal("xAB", pipeline.Correct("x", new AppSettings()));
    }

    [Fact]
    public void Skips_disabled_stages()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), _ => false),
            (Appender("B"), _ => true),
        });

        Assert.Equal("xB", pipeline.Correct("x", new AppSettings()));
    }

    [Fact]
    public void Empty_pipeline_is_passthrough()
    {
        var pipeline = new TextCorrectionPipeline(Array.Empty<(ITextCorrector, Func<AppSettings, bool>)>());

        Assert.Equal("unchanged ", pipeline.Correct("unchanged ", new AppSettings()));
    }

    [Fact]
    public void Gate_reads_current_settings()
    {
        var pipeline = new TextCorrectionPipeline(new (ITextCorrector, Func<AppSettings, bool>)[]
        {
            (Appender("A"), s => s.SpellCorrection),
        });

        Assert.Equal("x", pipeline.Correct("x", new AppSettings { SpellCorrection = false }));
        Assert.Equal("xA", pipeline.Correct("x", new AppSettings { SpellCorrection = true }));
    }

    [Fact]
    public void Null_stages_throws()
    {
        Assert.Throws<ArgumentNullException>(() => new TextCorrectionPipeline(null!));
    }
}
