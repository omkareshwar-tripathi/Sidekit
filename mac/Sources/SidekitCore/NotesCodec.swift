import Foundation

/// Pure JSON (de)serialization for the notes file. No I/O — the adapter (`JSONNotesStore`)
/// owns the file; this owns only the bytes ⇄ `[Note]` mapping, so the on-disk format and the
/// tolerant-decode rule are unit-testable without touching disk.
public enum NotesCodec {
    /// Stable, diff-friendly bytes for the current notes. Dates use the default `Codable`
    /// strategy (reference-date seconds) so timestamps round-trip *exactly* — no precision loss
    /// that could reorder two notes saved within the same second.
    public static func encode(_ notes: [Note]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // A well-formed `[Note]` always encodes; the `?? "[]"` is a total-function backstop.
        return (try? encoder.encode(notes)) ?? Data("[]".utf8)
    }

    /// Tolerant decode: malformed or empty input yields an empty list rather than throwing, so a
    /// corrupt `notes.json` degrades to "start fresh" instead of crashing the app at launch.
    public static func decode(_ data: Data) -> [Note] {
        (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }
}
