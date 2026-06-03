using System.IO.Compression;
using System.Security.Cryptography;
using SpeakType.Core.Models;

namespace SpeakType.Tests.Models;

public sealed class CoEditModelStoreTests : IDisposable
{
    private readonly string _tempDir;

    public CoEditModelStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "speaktype-coedittests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private static string Sha256Hex(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    /// <summary>Builds a zip (flat entries) and returns its raw bytes.</summary>
    private static byte[] MakeZip(params (string name, byte[] content)[] entries)
    {
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            foreach (var (name, content) in entries)
            {
                var entry = zip.CreateEntry(name);
                using var s = entry.Open();
                s.Write(content, 0, content.Length);
            }
        }

        return ms.ToArray();
    }

    /// <summary>A two-entry CoEdIT-shaped zip plus a model info whose parts split it in two.</summary>
    private static (byte[] zip, CoEditModelInfo info, FakePartDownloader downloader) BuildModel(
        byte[] encoder, byte[] decoder, int failuresBeforeSuccess = 0)
    {
        var zip = MakeZip(
            ("encoder_model.onnx", encoder),
            ("decoder_model_merged.onnx", decoder));
        var half = zip.Length / 2;
        var info = new CoEditModelInfo(
            new[] { "https://x/part00", "https://x/part01" },
            zip.Length,
            Sha256Hex(zip),
            new[] { "encoder_model.onnx", "decoder_model_merged.onnx" });
        var downloader = new FakePartDownloader { FailuresBeforeSuccess = failuresBeforeSuccess };
        downloader.ByUrl["https://x/part00"] = zip[..half];
        downloader.ByUrl["https://x/part01"] = zip[half..];
        return (zip, info, downloader);
    }

    /// <summary>Writes the bytes mapped to each requested URL; can fail the first N calls.</summary>
    private sealed class FakePartDownloader : IModelDownloader
    {
        public Dictionary<string, byte[]> ByUrl { get; } = new();
        public int FailuresBeforeSuccess { get; init; }
        public int Attempts { get; private set; }

        public Task DownloadAsync(
            string url, string destinationPath, IProgress<double>? progress, CancellationToken cancellationToken)
        {
            Attempts++;
            if (Attempts <= FailuresBeforeSuccess)
            {
                throw new IOException("simulated network failure");
            }

            File.WriteAllBytes(destinationPath, ByUrl[url]);
            progress?.Report(1.0);
            return Task.CompletedTask;
        }
    }

    [Fact]
    public async Task EnsureAsync_downloads_reassembles_extracts_and_returns_dir()
    {
        var encoder = new byte[] { 1, 2, 3, 4 };
        var decoder = new byte[] { 5, 6, 7, 8, 9 };
        var (_, info, downloader) = BuildModel(encoder, decoder);
        var store = new CoEditModelStore(downloader, _tempDir, info);

        var dir = await store.EnsureAsync(null, CancellationToken.None);

        Assert.Equal(store.ModelDirectory, dir);
        Assert.Equal(encoder, File.ReadAllBytes(Path.Combine(dir, "encoder_model.onnx")));
        Assert.Equal(decoder, File.ReadAllBytes(Path.Combine(dir, "decoder_model_merged.onnx")));
    }

    [Fact]
    public async Task EnsureAsync_leaves_no_work_directory_on_success()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 });
        var store = new CoEditModelStore(downloader, _tempDir, info);

        await store.EnsureAsync(null, CancellationToken.None);

        Assert.False(Directory.Exists(store.ModelDirectory + ".download"));
    }

    [Fact]
    public async Task GetInstalledModelDirectory_is_null_until_installed_then_returns_the_dir()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 });
        var store = new CoEditModelStore(downloader, _tempDir, info);

        Assert.Null(store.GetInstalledModelDirectory());

        await store.EnsureAsync(null, CancellationToken.None);

        Assert.Equal(store.ModelDirectory, store.GetInstalledModelDirectory());
    }

    [Fact]
    public async Task EnsureAsync_short_circuits_when_already_installed()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 });
        var store = new CoEditModelStore(downloader, _tempDir, info);
        Directory.CreateDirectory(store.ModelDirectory);
        File.WriteAllText(Path.Combine(store.ModelDirectory, "encoder_model.onnx"), "x");
        File.WriteAllText(Path.Combine(store.ModelDirectory, "decoder_model_merged.onnx"), "y");

        var dir = await store.EnsureAsync(null, CancellationToken.None);

        Assert.Equal(store.ModelDirectory, dir);
        Assert.Equal(0, downloader.Attempts); // nothing downloaded
    }

    [Fact]
    public async Task EnsureAsync_throws_when_the_reassembled_zip_hash_mismatches()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 });
        var corrupt = info with { ZipSha256 = new string('0', 64) }; // wrong hash
        var store = new CoEditModelStore(downloader, _tempDir, corrupt);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => store.EnsureAsync(null, CancellationToken.None));

        Assert.Null(store.GetInstalledModelDirectory());
        Assert.False(Directory.Exists(store.ModelDirectory + ".download"));
    }

    [Fact]
    public async Task EnsureAsync_throws_when_a_required_file_is_missing_from_the_zip()
    {
        // A zip that only contains the encoder — the decoder the info requires is absent.
        var zip = MakeZip(("encoder_model.onnx", new byte[] { 1, 2 }));
        var half = zip.Length / 2;
        var info = new CoEditModelInfo(
            new[] { "https://x/a", "https://x/b" },
            zip.Length,
            Sha256Hex(zip),
            new[] { "encoder_model.onnx", "decoder_model_merged.onnx" });
        var downloader = new FakePartDownloader();
        downloader.ByUrl["https://x/a"] = zip[..half];
        downloader.ByUrl["https://x/b"] = zip[half..];
        var store = new CoEditModelStore(downloader, _tempDir, info);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => store.EnsureAsync(null, CancellationToken.None));

        Assert.Null(store.GetInstalledModelDirectory());
    }

    [Fact]
    public async Task EnsureAsync_retries_then_succeeds()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 }, failuresBeforeSuccess: 1);
        var store = new CoEditModelStore(downloader, _tempDir, info);

        var dir = await store.EnsureAsync(null, CancellationToken.None);

        Assert.Equal(store.ModelDirectory, store.GetInstalledModelDirectory());
        // 1 forced failure + 2 successful part downloads on the second outer attempt.
        Assert.Equal(3, downloader.Attempts);
        Assert.True(File.Exists(Path.Combine(dir, "decoder_model_merged.onnx")));
    }

    [Fact]
    public async Task EnsureAsync_reports_progress_reaching_completion()
    {
        var (_, info, downloader) = BuildModel(new byte[] { 1 }, new byte[] { 2 });
        var store = new CoEditModelStore(downloader, _tempDir, info);
        var reported = new List<double>();
        var progress = new SyncProgress(reported.Add);

        await store.EnsureAsync(progress, CancellationToken.None);

        Assert.NotEmpty(reported);
        Assert.Equal(1.0, reported[^1], precision: 6); // ends at 100%
        Assert.All(reported, v => Assert.InRange(v, 0.0, 1.0));
    }

    /// <summary>Synchronous IProgress so the test observes reports deterministically.</summary>
    private sealed class SyncProgress : IProgress<double>
    {
        private readonly Action<double> _report;
        public SyncProgress(Action<double> report) => _report = report;
        public void Report(double value) => _report(value);
    }
}
