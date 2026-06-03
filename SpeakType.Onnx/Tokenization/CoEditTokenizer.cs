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
    // The LogicalName set on the EmbeddedResource in the .csproj.
    private const string ResourceName = "tokenizer.json";

    // Serializes extraction across threads. Without it, concurrent first-run extractors race on the
    // destination file: on Windows, File.Move(overwrite) throws UnauthorizedAccessException when
    // another thread already has the freshly-extracted file open for reading (POSIX rename on macOS
    // tolerates this, which is why it only failed on the CI runner).
    private static readonly object ExtractGate = new();

    private readonly Tokenizer _tokenizer;

    /// <summary>
    /// Loads the tokenizer bundled in this assembly. The <c>tokenizer.json</c> is an embedded
    /// resource, extracted to a per-user cache file on construction because Tokenizers.DotNet loads
    /// by file path. This is the production path: it works in a single-file published exe, where a
    /// content file beside the binary would not exist.
    /// </summary>
    public CoEditTokenizer()
        : this(ExtractBundledTokenizer())
    {
    }

    /// <param name="tokenizerJsonPath">Path to a HuggingFace <c>tokenizer.json</c>.</param>
    public CoEditTokenizer(string tokenizerJsonPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tokenizerJsonPath);
        if (!File.Exists(tokenizerJsonPath))
            throw new FileNotFoundException("CoEdIT tokenizer file not found.", tokenizerJsonPath);

        _tokenizer = new Tokenizer(vocabPath: tokenizerJsonPath);
    }

    // Materializes the embedded tokenizer.json to a stable per-user cache file and returns its path.
    // Idempotent: rewrites only when the file is missing or a different size (so a changed bundle or
    // a half-written file from a crashed run is refreshed), avoiding a 2.4 MB write on every startup.
    private static string ExtractBundledTokenizer()
    {
        using var resource = typeof(CoEditTokenizer).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"Embedded tokenizer resource '{ResourceName}' was not found.");

        var cacheDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SpeakType", "onnx");
        Directory.CreateDirectory(cacheDir);
        var path = Path.Combine(cacheDir, "coedit-tokenizer.json");

        // Serialize so exactly one thread writes the cache file; the rest wait, then see it present
        // and only read it. This is what makes the write race-free — the first thread does the move
        // before any reader opens the file, and every later thread skips the move entirely.
        lock (ExtractGate)
        {
            if (!File.Exists(path) || new FileInfo(path).Length != resource.Length)
            {
                // Write to a temp file then move into place, so a reader (this or another process)
                // never sees a partial file. Unique temp name avoids colliding with a leftover temp.
                var temp = $"{path}.{Guid.NewGuid():N}.tmp";
                using (var file = File.Create(temp))
                {
                    resource.CopyTo(file);
                }

                File.Move(temp, path, overwrite: true);
            }
        }

        return path;
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
