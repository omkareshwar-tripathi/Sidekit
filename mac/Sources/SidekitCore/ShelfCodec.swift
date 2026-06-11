import Foundation

/// Pure JSON (de)serialization for the Shelf index file. No I/O — the adapter (`JSONShelfStore`)
/// owns the file; this owns only the bytes ⇄ `[ShelfItem]` mapping, so the on-disk format and the
/// tolerant-decode rule are unit-testable without touching disk. Mirrors `NotesCodec`.
public enum ShelfCodec {
    /// Stable, diff-friendly bytes for the current items. Dates use the default `Codable` strategy
    /// (reference-date seconds) so `addedAt` round-trips exactly — expiry timing stays precise.
    public static func encode(_ items: [ShelfItem]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(items)) ?? Data("[]".utf8)
    }

    /// Tolerant decode: malformed or empty input yields an empty list rather than throwing, so a
    /// corrupt `shelf.json` degrades to "start fresh" instead of crashing the app at launch.
    public static func decode(_ data: Data) -> [ShelfItem] {
        (try? JSONDecoder().decode([ShelfItem].self, from: data)) ?? []
    }
}
