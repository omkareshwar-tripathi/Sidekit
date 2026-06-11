namespace Sidekit.Core.Models;

/// <summary>
/// Manages the on-disk set of Whisper models: resolving their directory,
/// reporting what is installed, and ensuring a named model is present and valid.
/// </summary>
public interface IModelStore
{
    /// <summary>The directory where model files live.</summary>
    string ModelsDirectory { get; }

    /// <summary>
    /// The local path of the named model if its file exists on disk (a
    /// lightweight existence check — no hashing), otherwise <c>null</c>.
    /// </summary>
    string? GetInstalledModelPath(string modelName);

    /// <summary>
    /// Ensures the named model is present and valid (correct size and SHA256),
    /// downloading it if needed, and returns its local path. Throws if the model
    /// cannot be made valid.
    /// </summary>
    Task<string> EnsureAsync(
        string modelName,
        IProgress<double>? progress,
        CancellationToken cancellationToken);
}
