using System.IO.Compression;
using System.Security.Cryptography;

namespace SpeakType.Core.Models;

/// <summary>
/// Acquires the multi-part CoEdIT model into a directory of ONNX files. Downloads
/// each part (with retry), concatenates them into one zip, verifies the zip by
/// size + SHA256, extracts it, and only then atomically swaps it into place. A
/// failed acquisition never leaves a half-installed directory: extraction happens
/// in a sibling work directory that is removed on both success and failure, and
/// the final directory is replaced only once every required file is present.
/// </summary>
public sealed class CoEditModelStore
{
    private const int MaxAttempts = 3;
    private const string ModelDirName = "coedit-large";

    private readonly IModelDownloader _downloader;
    private readonly string _modelsDirectory;
    private readonly CoEditModelInfo _info;

    public CoEditModelStore(
        IModelDownloader downloader,
        string modelsDirectory,
        CoEditModelInfo? info = null)
    {
        ArgumentNullException.ThrowIfNull(downloader);
        ArgumentNullException.ThrowIfNull(modelsDirectory);
        _downloader = downloader;
        _modelsDirectory = modelsDirectory;
        _info = info ?? CoEditModelCatalog.Default;
    }

    /// <summary>The default per-user models directory, shared with the Whisper model store.</summary>
    public static string DefaultModelsDirectory => ModelStore.DefaultModelsDirectory;

    /// <summary>The directory the model's ONNX files live in once installed.</summary>
    public string ModelDirectory => Path.Combine(_modelsDirectory, ModelDirName);

    /// <summary>The installed model directory, or null if any required file is missing.</summary>
    public string? GetInstalledModelDirectory() =>
        IsComplete(ModelDirectory) ? ModelDirectory : null;

    public async Task<string> EnsureAsync(IProgress<double>? progress, CancellationToken cancellationToken)
    {
        var finalDir = ModelDirectory;
        if (IsComplete(finalDir))
        {
            return finalDir;
        }

        Directory.CreateDirectory(_modelsDirectory);
        var workDir = finalDir + ".download";
        Exception? lastError = null;

        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                DeleteDir(workDir);
                Directory.CreateDirectory(workDir);

                var zipPath = Path.Combine(workDir, "model.zip");
                await DownloadAndReassembleAsync(zipPath, progress, cancellationToken).ConfigureAwait(false);

                if (VerifyZip(zipPath))
                {
                    var extractDir = Path.Combine(workDir, "extract");
                    ZipFile.ExtractToDirectory(zipPath, extractDir);
                    if (IsComplete(extractDir))
                    {
                        ReplaceDir(finalDir, extractDir);
                        DeleteDir(workDir);
                        return finalDir;
                    }
                }
            }
            catch (OperationCanceledException)
            {
                DeleteDir(workDir);
                throw;
            }
            catch (Exception ex)
            {
                lastError = ex; // network/I/O/extraction failure: keep it for the report, then retry.
            }

            DeleteDir(workDir);
        }

        throw new InvalidOperationException(
            $"Failed to acquire a valid CoEdIT model after {MaxAttempts} attempts.", lastError);
    }

    private async Task DownloadAndReassembleAsync(
        string zipPath, IProgress<double>? progress, CancellationToken cancellationToken)
    {
        var n = _info.PartUrls.Count;
        var partPaths = new List<string>(n);
        for (var i = 0; i < n; i++)
        {
            var partPath = zipPath + $".part{i}";
            var index = i;
            // Map each part's 0..1 to the overall (index + fraction) / n so the bar advances smoothly.
            var partProgress = progress is null
                ? null
                : new RelayProgress(f => progress.Report((index + f) / n));
            await _downloader.DownloadAsync(_info.PartUrls[i], partPath, partProgress, cancellationToken)
                .ConfigureAwait(false);
            partPaths.Add(partPath);
        }

        await using (var output = File.Create(zipPath))
        {
            foreach (var partPath in partPaths)
            {
                await using var input = File.OpenRead(partPath);
                await input.CopyToAsync(output, cancellationToken).ConfigureAwait(false);
            }
        }

        foreach (var partPath in partPaths)
        {
            File.Delete(partPath);
        }
    }

    private bool IsComplete(string dir) =>
        _info.RequiredFiles.All(f => File.Exists(Path.Combine(dir, f)));

    private bool VerifyZip(string path)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != _info.ZipSizeBytes)
        {
            return false;
        }

        using var stream = File.OpenRead(path);
        var hex = Convert.ToHexString(SHA256.HashData(stream));
        return string.Equals(hex, _info.ZipSha256, StringComparison.OrdinalIgnoreCase);
    }

    private static void ReplaceDir(string finalDir, string sourceDir)
    {
        DeleteDir(finalDir);
        Directory.Move(sourceDir, finalDir);
    }

    private static void DeleteDir(string dir)
    {
        if (Directory.Exists(dir))
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    /// <summary>Synchronous IProgress relay (no SynchronizationContext hop, unlike Progress&lt;T&gt;).</summary>
    private sealed class RelayProgress : IProgress<double>
    {
        private readonly Action<double> _report;
        public RelayProgress(Action<double> report) => _report = report;
        public void Report(double value) => _report(value);
    }
}
