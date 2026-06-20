using System.Net;
using Sidekit.Core.Models;

namespace Sidekit.Tests.Models;

public sealed class HttpModelDownloaderTests : IDisposable
{
    private readonly string _tempDir;

    public HttpModelDownloaderTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "sidekit-dltests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private static byte[] Payload() =>
        Enumerable.Range(0, 200_000).Select(i => (byte)(i % 251)).ToArray();

    private string DestPath() => Path.Combine(_tempDir, "out.bin");

    /// <summary>Returns a fixed response regardless of request.</summary>
    private sealed class FakeHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpResponseMessage> _factory;

        public FakeHttpMessageHandler(Func<HttpResponseMessage> factory) => _factory = factory;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(_factory());
        }
    }

    /// <summary>Content that refuses to advertise a length (no Content-Length header).</summary>
    private sealed class NoLengthContent : HttpContent
    {
        private readonly byte[] _bytes;

        public NoLengthContent(byte[] bytes) => _bytes = bytes;

        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) =>
            stream.WriteAsync(_bytes, 0, _bytes.Length);

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }

    /// <summary>Synchronous progress collector (deterministic, unlike System.Progress&lt;T&gt;).</summary>
    private sealed class ProgressCollector : IProgress<double>
    {
        public List<double> Values { get; } = new();

        public void Report(double value) => Values.Add(value);
    }

    private static HttpClient ClientReturning(Func<HttpResponseMessage> factory) =>
        new HttpClient(new FakeHttpMessageHandler(factory));

    [Fact]
    public async Task DownloadAsync_writes_body_to_path_with_content_length()
    {
        var payload = Payload();
        using var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(payload),
        });
        var downloader = new HttpModelDownloader(client);

        await downloader.DownloadAsync("https://example/model", DestPath(), null, CancellationToken.None);

        Assert.Equal(payload, await File.ReadAllBytesAsync(DestPath()));
    }

    [Fact]
    public async Task DownloadAsync_reports_progress_ending_at_one()
    {
        var payload = Payload();
        using var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(payload),
        });
        var downloader = new HttpModelDownloader(client);
        var progress = new ProgressCollector();

        await downloader.DownloadAsync("https://example/model", DestPath(), progress, CancellationToken.None);

        Assert.NotEmpty(progress.Values);
        for (var i = 1; i < progress.Values.Count; i++)
        {
            Assert.True(progress.Values[i] >= progress.Values[i - 1], "progress must be non-decreasing");
        }

        Assert.Equal(1.0, progress.Values[^1]);
    }

    [Fact]
    public async Task DownloadAsync_writes_correctly_without_content_length()
    {
        var payload = Payload();
        using var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new NoLengthContent(payload),
        });
        var downloader = new HttpModelDownloader(client);
        var progress = new ProgressCollector();

        await downloader.DownloadAsync("https://example/model", DestPath(), progress, CancellationToken.None);

        Assert.Equal(payload, await File.ReadAllBytesAsync(DestPath()));
    }

    [Fact]
    public async Task DownloadAsync_throws_on_non_success_status()
    {
        using var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.NotFound));
        var downloader = new HttpModelDownloader(client);

        await Assert.ThrowsAsync<HttpRequestException>(
            () => downloader.DownloadAsync("https://example/missing", DestPath(), null, CancellationToken.None));
    }

    [Fact]
    public async Task DownloadAsync_throws_when_cancelled()
    {
        var payload = Payload();
        using var client = ClientReturning(() => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(payload),
        });
        var downloader = new HttpModelDownloader(client);
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => downloader.DownloadAsync("https://example/model", DestPath(), null, cts.Token));
    }
}
