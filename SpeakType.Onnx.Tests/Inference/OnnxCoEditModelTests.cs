using SpeakType.Onnx.Inference;
using SpeakType.Onnx.Tokenization;
using Xunit;

namespace SpeakType.Onnx.Tests.Inference;

/// <summary>
/// End-to-end tests against the real CoEdIT model. They run only when the
/// environment variable <c>COEDIT_MODEL_DIR</c> points at a folder containing
/// <c>encoder_model.onnx</c> + <c>decoder_model_merged.onnx</c> — the ~2.4 GB
/// model is not in git or CI, so these are skipped there.
/// </summary>
public sealed class OnnxCoEditModelTests
{
    private static (string Enc, string Dec)? ModelPaths()
    {
        var dir = Environment.GetEnvironmentVariable("COEDIT_MODEL_DIR");
        if (string.IsNullOrWhiteSpace(dir))
            return null;
        var enc = Path.Combine(dir, "encoder_model.onnx");
        var dec = Path.Combine(dir, "decoder_model_merged.onnx");
        return File.Exists(enc) && File.Exists(dec) ? (enc, dec) : null;
    }

    private static CoEditPolisher Polisher(OnnxCoEditModel model) =>
        new(new CoEditTokenizer(), model);

    [SkippableTheory]
    [InlineData("he go to school every days.")]
    [InlineData("she dont like apples and they was rotten.")]
    public void Polishes_grammatically_wrong_text(string input)
    {
        var m = ModelPaths();
        Skip.If(m is null, "Set COEDIT_MODEL_DIR to the fp16 model folder to run this.");

        using var model = new OnnxCoEditModel(m.Value.Enc, m.Value.Dec);
        var result = Polisher(model).Polish(input);

        Assert.False(string.IsNullOrWhiteSpace(result));
        Assert.NotEqual(input, result);                   // it actually corrected something
        Assert.True(char.IsUpper(result.TrimStart()[0]));  // proper capitalization
    }

    [SkippableFact]
    public void Polishes_already_correct_text_without_emptying_it()
    {
        var m = ModelPaths();
        Skip.If(m is null, "Set COEDIT_MODEL_DIR to the fp16 model folder to run this.");

        using var model = new OnnxCoEditModel(m.Value.Enc, m.Value.Dec);
        var result = Polisher(model).Polish("Hello world.");

        Assert.False(string.IsNullOrWhiteSpace(result));
    }
}
