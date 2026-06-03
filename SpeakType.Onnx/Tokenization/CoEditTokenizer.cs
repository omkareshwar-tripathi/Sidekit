using Tokenizers.DotNet;

namespace SpeakType.Onnx.Tokenization;

/// <summary>
/// Tokenizer for the CoEdIT / Flan-T5 model, backed by the HuggingFace tokenizer
/// (Tokenizers.DotNet) and the bundled SentencePiece <c>tokenizer.json</c>.
/// <para>
/// Encoding appends the T5 end-of-sequence token (id 1) via the tokenizer's own
/// post-processor; decoding strips special tokens, returning clean text.
/// </para>
/// </summary>
public sealed class CoEditTokenizer
{
    private readonly Tokenizer _tokenizer;

    /// <summary>Path to the <c>tokenizer.json</c> bundled next to this assembly.</summary>
    public static string DefaultTokenizerPath =>
        Path.Combine(AppContext.BaseDirectory, "assets", "tokenizer.json");

    /// <param name="tokenizerJsonPath">Path to a HuggingFace <c>tokenizer.json</c>.</param>
    public CoEditTokenizer(string tokenizerJsonPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tokenizerJsonPath);
        if (!File.Exists(tokenizerJsonPath))
            throw new FileNotFoundException("CoEdIT tokenizer file not found.", tokenizerJsonPath);

        _tokenizer = new Tokenizer(vocabPath: tokenizerJsonPath);
    }

    /// <summary>Encodes text to token ids, with the trailing EOS token included.</summary>
    public IReadOnlyList<int> Encode(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        uint[] ids = _tokenizer.Encode(text);
        var result = new int[ids.Length];
        for (int i = 0; i < ids.Length; i++)
            result[i] = (int)ids[i];
        return result;
    }

    /// <summary>Decodes token ids back to text, stripping special tokens (e.g. EOS).</summary>
    public string Decode(IReadOnlyList<int> ids)
    {
        ArgumentNullException.ThrowIfNull(ids);

        var unsigned = new uint[ids.Count];
        for (int i = 0; i < ids.Count; i++)
            unsigned[i] = (uint)ids[i];
        return _tokenizer.Decode(unsigned);
    }
}
