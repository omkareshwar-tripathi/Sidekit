using System.Security.Cryptography;
using SpeakType.Core.Models;

namespace SpeakType.Tests.Models;

public sealed class ModelStoreTests : IDisposable
{
    private readonly string _tempDir;

    public ModelStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "speaktype-modeltests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private static string Sha256Hex(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static ModelInfo InfoFor(string name, byte[] bytes) =>
        new(name, $"https://example/{name}", bytes.Length, Sha256Hex(bytes));

    private string PathFor(string name) => Path.Combine(_tempDir, $"ggml-{name}.bin");

    /// <summary>
    /// Configurable fake downloader: writes <see cref="Bytes"/> to the
    /// destination, optionally failing the first <see cref="FailuresBeforeSuccess"/>
    /// attempts. Records how many times it was invoked.
    /// </summary>
    private sealed class FakeDownloader : IModelDownloader
    {
        public byte[] Bytes { get; init; } = Array.Empty<byte>();
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

            File.WriteAllBytes(destinationPath, Bytes);
            return Task.CompletedTask;
        }
    }

    [Fact]
    public async Task EnsureAsync_installs_when_download_verifies()
    {
        var bytes = new byte[] { 1, 2, 3, 4, 5 };
        var info = InfoFor("good", bytes);
        var fake = new FakeDownloader { Bytes = bytes };
        var store = new ModelStore(fake, _tempDir, CatalogOf(info));

        var path = await store.EnsureAsync("good", null, CancellationToken.None);

        Assert.Equal(PathFor("good"), path);
        Assert.True(File.Exists(path));
        Assert.Equal(bytes, File.ReadAllBytes(path));
    }

    [Fact]
    public async Task EnsureAsync_throws_and_cleans_temp_when_download_never_verifies()
    {
        var expected = new byte[] { 1, 2, 3, 4, 5 };
        var info = InfoFor("good", expected);
        // Fake always writes wrong-length bytes, so verification fails every attempt.
        var fake = new FakeDownloader { Bytes = new byte[] { 9, 9 } };
        var store = new ModelStore(fake, _tempDir, CatalogOf(info));

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => store.EnsureAsync("good", null, CancellationToken.None));

        Assert.False(File.Exists(PathFor("good")));
        Assert.False(File.Exists(PathFor("good") + ".download"));
        Assert.Equal(3, fake.Attempts);
    }

    [Fact]
    public async Task EnsureAsync_failed_switch_leaves_existing_model_untouched()
    {
        var oldBytes = new byte[] { 10, 20, 30 };
        var oldInfo = InfoFor("old", oldBytes);
        File.WriteAllBytes(PathFor("old"), oldBytes);

        var newInfo = InfoFor("new", new byte[] { 1, 2, 3, 4 });
        // Fake writes bad bytes for the new model, so the switch always fails.
        var fake = new FakeDownloader { Bytes = new byte[] { 0 } };
        var store = new ModelStore(fake, _tempDir, CatalogOf(oldInfo, newInfo));

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => store.EnsureAsync("new", null, CancellationToken.None));

        // Old model still present and still valid; new model not installed.
        Assert.True(File.Exists(PathFor("old")));
        Assert.Equal(oldBytes, File.ReadAllBytes(PathFor("old")));
        Assert.False(File.Exists(PathFor("new")));
    }

    [Fact]
    public async Task EnsureAsync_short_circuits_when_already_installed_and_valid()
    {
        var bytes = new byte[] { 7, 7, 7 };
        var info = InfoFor("good", bytes);
        File.WriteAllBytes(PathFor("good"), bytes);
        var fake = new FakeDownloader { Bytes = bytes };
        var store = new ModelStore(fake, _tempDir, CatalogOf(info));

        var path = await store.EnsureAsync("good", null, CancellationToken.None);

        Assert.Equal(PathFor("good"), path);
        Assert.Equal(0, fake.Attempts);
    }

    [Fact]
    public async Task EnsureAsync_redownloads_when_existing_file_is_corrupt()
    {
        var goodBytes = new byte[] { 1, 2, 3, 4, 5 };
        var info = InfoFor("good", goodBytes);
        File.WriteAllBytes(PathFor("good"), new byte[] { 0, 0 }); // wrong content on disk
        var fake = new FakeDownloader { Bytes = goodBytes };
        var store = new ModelStore(fake, _tempDir, CatalogOf(info));

        var path = await store.EnsureAsync("good", null, CancellationToken.None);

        Assert.Equal(1, fake.Attempts);
        Assert.Equal(goodBytes, File.ReadAllBytes(path));
    }

    [Fact]
    public async Task EnsureAsync_retries_then_succeeds()
    {
        var bytes = new byte[] { 4, 5, 6 };
        var info = InfoFor("good", bytes);
        var fake = new FakeDownloader { Bytes = bytes, FailuresBeforeSuccess = 1 };
        var store = new ModelStore(fake, _tempDir, CatalogOf(info));

        var path = await store.EnsureAsync("good", null, CancellationToken.None);

        Assert.True(File.Exists(path));
        Assert.Equal(2, fake.Attempts);
    }

    [Fact]
    public async Task EnsureAsync_throws_for_unknown_model()
    {
        var fake = new FakeDownloader();
        var store = new ModelStore(fake, _tempDir, CatalogOf(InfoFor("good", new byte[] { 1 })));

        await Assert.ThrowsAsync<ArgumentException>(
            () => store.EnsureAsync("nope", null, CancellationToken.None));
    }

    [Fact]
    public void GetInstalledModelPath_returns_path_when_present_else_null()
    {
        var store = new ModelStore(new FakeDownloader(), _tempDir, CatalogOf(InfoFor("good", new byte[] { 1 })));

        Assert.Null(store.GetInstalledModelPath("good"));

        File.WriteAllBytes(PathFor("good"), new byte[] { 1 });
        Assert.Equal(PathFor("good"), store.GetInstalledModelPath("good"));
    }

    [Fact]
    public async Task GetInstalledModelPath_resolves_non_canonical_casing()
    {
        var bytes = new byte[] { 1, 2, 3 };
        var info = InfoFor("good", bytes);
        var store = new ModelStore(new FakeDownloader { Bytes = bytes }, _tempDir, CatalogOf(info));

        // Install via a non-canonical name; the file lands at the canonical ggml-good.bin.
        await store.EnsureAsync("GOOD", null, CancellationToken.None);

        // A differently-cased query must still resolve to the installed canonical file.
        Assert.Equal(PathFor("good"), store.GetInstalledModelPath("GOOD"));
    }

    private static IReadOnlyDictionary<string, ModelInfo> CatalogOf(params ModelInfo[] infos)
    {
        var dict = new Dictionary<string, ModelInfo>(StringComparer.OrdinalIgnoreCase);
        foreach (var info in infos)
        {
            dict[info.Name] = info;
        }

        return dict;
    }
}
