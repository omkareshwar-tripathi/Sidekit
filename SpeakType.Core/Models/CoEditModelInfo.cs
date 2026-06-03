namespace SpeakType.Core.Models;

/// <summary>
/// The CoEdIT (Flan-T5) ONNX model release: the ordered list of part URLs that
/// concatenate into one zip, the reassembled zip's expected size + SHA256
/// (lowercase hex), and the filenames that must be present after extraction for
/// the model to be usable. Hosted split because a single asset exceeds GitHub's
/// 2 GiB release-asset cap.
/// </summary>
public sealed record CoEditModelInfo(
    IReadOnlyList<string> PartUrls,
    long ZipSizeBytes,
    string ZipSha256,
    IReadOnlyList<string> RequiredFiles);

/// <summary>The single CoEdIT model SpeakType installs (Release <c>coedit-large-v1</c>).</summary>
public static class CoEditModelCatalog
{
    private const string ReleaseBase =
        "https://github.com/omkareshwar-tripathi/SpeakType/releases/download/coedit-large-v1";

    /// <summary>
    /// fp16 encoder + fp32 merged decoder, split into two &lt;2 GiB parts. Size + SHA256 are
    /// of the reassembled <c>coedit-large-fp16.zip</c> (from the export's metadata sidecar).
    /// </summary>
    public static CoEditModelInfo Default { get; } = new(
        new[]
        {
            $"{ReleaseBase}/coedit-large-fp16.zip.part00",
            $"{ReleaseBase}/coedit-large-fp16.zip.part01",
        },
        2393073125,
        "d74ee0e13e40ce39be0926efb7eeb705ac1ec70507563a505a34721672a918ef",
        new[] { "encoder_model.onnx", "decoder_model_merged.onnx" });
}
