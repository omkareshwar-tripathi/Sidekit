namespace SpeakType.Core.Models;

/// <summary>
/// Streaming <see cref="IModelDownloader"/> over an injected <see cref="HttpClient"/>.
/// Borrows the client (the Brick 14 composition root owns and disposes it), so this
/// type is not <see cref="IDisposable"/>. Each call performs a single attempt;
/// <see cref="ModelStore"/> owns retry, verification, and atomic install.
/// </summary>
public sealed class HttpModelDownloader : IModelDownloader
{
    // 80 KB — matches the default Stream.CopyToAsync chunk size.
    private const int BufferSize = 81920;

    private readonly HttpClient _httpClient;

    public HttpModelDownloader(HttpClient httpClient)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        _httpClient = httpClient;
    }

    public async Task DownloadAsync(
        string url,
        string destinationPath,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        using var response = await _httpClient
            .GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        var total = response.Content.Headers.ContentLength;

        await using var httpStream = await response.Content
            .ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        await using var fileStream = File.Create(destinationPath);

        var buffer = new byte[BufferSize];
        long received = 0;
        int read;
        while ((read = await httpStream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
        {
            await fileStream.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
            received += read;
            if (total is > 0)
            {
                progress?.Report((double)received / total.Value);
            }
        }
    }
}
