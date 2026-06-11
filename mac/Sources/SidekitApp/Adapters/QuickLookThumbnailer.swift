import AppKit
import QuickLookThumbnailing

/// Generates QuickLook *content* thumbnails for shelved files (a rendered preview — the image, a
/// document's first page, a text file's first lines) and caches them. Requesting `.thumbnail`
/// (not `.icon`) means QuickLook returns nil for a type it can't actually preview, so the tile's kind
/// glyph stays the genuine fallback rather than being masked by a generic file icon.
///
/// Lives on the main actor, so the cached `NSImage`s never cross an actor boundary (Swift 6 Sendable).
/// Backed by `NSCache` (count cap + automatic memory-pressure eviction) so it can't grow without bound
/// over a long-running session — entries for removed/expired items age out on their own. A nil outcome
/// is cached too (an `Entry` boxing `nil`), so an un-previewable file isn't re-generated on every
/// scroll. The cache is keyed by display scale + on-disk path, so a panel moved to a different-scale
/// display re-generates at the right resolution instead of serving a stale bitmap.
@MainActor
final class ShelfThumbnailer {
    /// Boxes an optional image so the cache can record "tried, got nothing" (a negative result)
    /// distinctly from "never tried" — `NSCache` stores objects, not optionals.
    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()

    init() { cache.countLimit = 256 }

    /// The already-generated thumbnail for this file at this scale, if any — a synchronous peek so a
    /// tile can show a warm thumbnail on its first frame instead of flashing the glyph.
    func cached(for url: URL, scale: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, scale))?.image
    }

    /// A QuickLook content thumbnail for the file at `url`, generated once per (scale, path) and cached
    /// (including a nil outcome). Returns nil when QuickLook can't preview the type, so the caller keeps
    /// its placeholder glyph.
    func thumbnail(for url: URL, scale: CGFloat, size: CGSize) async -> NSImage? {
        let cacheKey = key(url, scale)
        if let entry = cache.object(forKey: cacheKey) { return entry.image }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: scale, representationTypes: [.thumbnail, .lowQualityThumbnail])
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
        cache.setObject(Entry(image), forKey: cacheKey)
        return image
    }

    private func key(_ url: URL, _ scale: CGFloat) -> NSString {
        "\(Int(scale))x:\(url.path)" as NSString
    }
}
