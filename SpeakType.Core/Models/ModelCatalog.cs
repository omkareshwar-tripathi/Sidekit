using SpeakType.Core.Settings;

namespace SpeakType.Core.Models;

/// <summary>
/// A Whisper ggml model available for download: its short name, download URL,
/// expected byte size, and SHA256 (lowercase hex). The size and SHA256 are the
/// HuggingFace Git-LFS pointer values (verified at milestone M2).
/// </summary>
public sealed record ModelInfo(string Name, string Url, long SizeBytes, string Sha256);

/// <summary>
/// The fixed set of Whisper models SpeakType can install. Keyed by model name
/// (case-insensitive).
/// </summary>
public static class ModelCatalog
{
    private static string UrlFor(string name) =>
        $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{name}.bin";

    /// <summary>
    /// Returns <paramref name="modelName"/> when it names a known model, otherwise the default
    /// (<see cref="AppSettings.DefaultModelSize"/>). Coerces a persisted/typed model name to a real
    /// catalog entry before it is downloaded or loaded, so a stale or unknown name never reaches the store.
    /// </summary>
    public static string Resolve(string? modelName) =>
        modelName is not null && All.ContainsKey(modelName) ? modelName : AppSettings.DefaultModelSize;

    /// <summary>All known models, keyed by name (case-insensitive).</summary>
    public static IReadOnlyDictionary<string, ModelInfo> All { get; } =
        new Dictionary<string, ModelInfo>(StringComparer.OrdinalIgnoreCase)
        {
            ["tiny.en"] = new ModelInfo(
                "tiny.en", UrlFor("tiny.en"), 77704715,
                "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"),
            ["base.en"] = new ModelInfo(
                "base.en", UrlFor("base.en"), 147964211,
                "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"),
            ["small.en"] = new ModelInfo(
                "small.en", UrlFor("small.en"), 487614201,
                "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"),
        };
}
