namespace Sidekit.Core.Models;

/// <summary>
/// Performs a single download attempt. The real <c>HttpClient</c>-based
/// implementation arrives in Brick 6b; tests use a fake.
/// </summary>
public interface IModelDownloader
{
    /// <summary>
    /// Downloads <paramref name="url"/> to <paramref name="destinationPath"/>,
    /// reporting progress as a fraction in [0, 1]. Throws on any network or I/O
    /// failure.
    /// </summary>
    Task DownloadAsync(
        string url,
        string destinationPath,
        IProgress<double>? progress,
        CancellationToken cancellationToken);
}
