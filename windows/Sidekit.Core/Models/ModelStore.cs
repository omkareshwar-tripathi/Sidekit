using System.Security.Cryptography;

namespace Sidekit.Core.Models;

/// <summary>
/// File-backed <see cref="IModelStore"/>. Verifies models by size + SHA256,
/// downloads (with retry) via an injected <see cref="IModelDownloader"/>, and
/// installs atomically via a temp file + move. A failed switch never touches an
/// already-installed model: each model has its own filename, and the final path
/// is only replaced once a freshly downloaded copy verifies.
/// </summary>
public sealed class ModelStore : IModelStore
{
    private const int MaxAttempts = 3;

    private readonly IModelDownloader _downloader;
    private readonly string _modelsDirectory;
    private readonly IReadOnlyDictionary<string, ModelInfo> _catalog;

    public ModelStore(
        IModelDownloader downloader,
        string modelsDirectory,
        IReadOnlyDictionary<string, ModelInfo>? catalog = null)
    {
        ArgumentNullException.ThrowIfNull(downloader);
        ArgumentNullException.ThrowIfNull(modelsDirectory);
        _downloader = downloader;
        _modelsDirectory = modelsDirectory;
        _catalog = catalog ?? ModelCatalog.All;
    }

    /// <summary>The default per-user models directory for the composition root.</summary>
    public static string DefaultModelsDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        AppInfo.Name,
        "models");

    public string ModelsDirectory => _modelsDirectory;

    public string? GetInstalledModelPath(string modelName)
    {
        // Resolve through the catalog so the canonical (case-normalized) filename is used,
        // matching EnsureAsync — otherwise a non-canonical name like "BASE.EN" would miss
        // the installed "ggml-base.en.bin" on a case-sensitive filesystem.
        if (!_catalog.TryGetValue(modelName, out var info))
        {
            return null;
        }

        var p = PathFor(info.Name);
        return File.Exists(p) ? p : null;
    }

    public async Task<string> EnsureAsync(
        string modelName,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        if (!_catalog.TryGetValue(modelName, out var info))
        {
            throw new ArgumentException($"Unknown model '{modelName}'.", nameof(modelName));
        }

        var finalPath = PathFor(info.Name);
        if (File.Exists(finalPath) && Verify(finalPath, info))
        {
            return finalPath;
        }

        Directory.CreateDirectory(_modelsDirectory);
        var tempPath = finalPath + ".download";
        Exception? lastError = null;

        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                await _downloader.DownloadAsync(info.Url, tempPath, progress, cancellationToken)
                    .ConfigureAwait(false);

                if (Verify(tempPath, info))
                {
                    File.Move(tempPath, finalPath, overwrite: true);
                    return finalPath;
                }
            }
            catch (OperationCanceledException)
            {
                DeleteIfExists(tempPath);
                throw;
            }
            catch (Exception ex)
            {
                lastError = ex; // network or I/O failure: keep it for the final report, then retry.
            }

            DeleteIfExists(tempPath);
        }

        throw new InvalidOperationException(
            $"Failed to download a valid '{info.Name}' model after {MaxAttempts} attempts.",
            lastError);
    }

    private string PathFor(string name) => Path.Combine(_modelsDirectory, $"ggml-{name}.bin");

    private static bool Verify(string path, ModelInfo info)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != info.SizeBytes)
        {
            return false;
        }

        using var stream = File.OpenRead(path);
        var hash = SHA256.HashData(stream);
        var hex = Convert.ToHexString(hash);
        return string.Equals(hex, info.Sha256, StringComparison.OrdinalIgnoreCase);
    }

    private static void DeleteIfExists(string path)
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }
}
