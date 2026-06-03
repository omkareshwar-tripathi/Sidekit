using SpeakType.Core.Polishing;
using SpeakType.Onnx.Tokenization;

namespace SpeakType.Onnx.Inference;

/// <summary>
/// CoEdIT (Flan-T5) text polisher. Tokenizes <c>instruction + text</c>, runs the
/// encoder once, then greedily decodes one token at a time until the model emits
/// EOS (or a safety cap is hit), and detokenizes the result.
/// <para>
/// The decode loop is pure logic; all ONNX/tensor work lives behind
/// <see cref="ICoEditModel"/> so this class is fully unit-testable with a fake model.
/// </para>
/// </summary>
public sealed class CoEditPolisher : ITextPolisher
{
    // From the CoEdIT/Flan-T5 config.json.
    private const int DecoderStartTokenId = 0; // pad token starts the decoder
    private const int EosTokenId = 1;

    private readonly CoEditTokenizer _tokenizer;
    private readonly ICoEditModel _model;
    private readonly string _instruction;
    private readonly int _maxNewTokens;

    /// <param name="instruction">Prepended to every input (default: conservative grammar fix).</param>
    /// <param name="maxNewTokens">Safety cap on generated tokens (T5 supports 512 positions).</param>
    public CoEditPolisher(
        CoEditTokenizer tokenizer,
        ICoEditModel model,
        string instruction = "Fix the grammar: ",
        int maxNewTokens = 512)
    {
        ArgumentNullException.ThrowIfNull(tokenizer);
        ArgumentNullException.ThrowIfNull(model);
        ArgumentNullException.ThrowIfNull(instruction);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxNewTokens);

        _tokenizer = tokenizer;
        _model = model;
        _instruction = instruction;
        _maxNewTokens = maxNewTokens;
    }

    public string Polish(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var sourceIds = _tokenizer.Encode(_instruction + text);
        var encoderOutput = _model.Encode(sourceIds);

        var decoded = new List<int>(_maxNewTokens + 1) { DecoderStartTokenId };
        for (int step = 0; step < _maxNewTokens; step++)
        {
            var logits = _model.DecodeNextLogits(encoderOutput, decoded);
            int next = ArgMax(logits);
            if (next == EosTokenId)
                break;
            decoded.Add(next);
        }

        // Drop the leading decoder-start token; Decode strips any other special tokens.
        return _tokenizer.Decode(decoded.GetRange(1, decoded.Count - 1));
    }

    private static int ArgMax(float[] logits)
    {
        int best = 0;
        for (int i = 1; i < logits.Length; i++)
            if (logits[i] > logits[best])
                best = i;
        return best;
    }
}
