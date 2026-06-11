import Foundation

/// Pure JSON (de)serialization for the dictation-trail file. No I/O — the adapter owns the file;
/// this owns only the bytes ⇄ `[DictationHistoryEntry]` mapping, so the on-disk format and the
/// tolerant-decode rule are unit-testable without touching disk. Mirrors `NotesCodec`.
public enum HistoryCodec {
    /// Stable, diff-friendly bytes for the current trail. Dates use the default `Codable` strategy
    /// (reference-date seconds) so timestamps round-trip exactly. A malformed encode falls back to
    /// `[]` as a total-function backstop.
    public static func encode(_ entries: [DictationHistoryEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }

    /// Tolerant decode: malformed or empty input yields an empty list rather than throwing, so a
    /// corrupt `history.json` degrades to "start fresh" instead of crashing the app at launch.
    public static func decode(_ data: Data) -> [DictationHistoryEntry] {
        (try? JSONDecoder().decode([DictationHistoryEntry].self, from: data)) ?? []
    }
}
