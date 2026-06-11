import Foundation
import SidekitCore

/// On-disk persistence for the dictation trail, at
/// `~/Library/Application Support/Sidekit/history.json` (same folder as `notes.json`).
///
/// Tolerant load (missing or corrupt file → empty list, logged via `Diag`); atomic write with a
/// single retry. The trail is small and only written once per dictation, so saves are immediate
/// (no debounce) and run synchronously on the calling main actor. `@unchecked Sendable`: `url` is
/// immutable and there's no mutable shared state.
final class JSONHistoryStore: @unchecked Sendable {
    private let url: URL

    init() {
        self.url = AppPaths.applicationSupport.appendingPathComponent("history.json")
    }

    func load() -> [DictationHistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] } // first run
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("history: could not read \(url.lastPathComponent)")
            return []
        }
        let entries = HistoryCodec.decode(data)
        if entries.isEmpty && !data.isEmpty {
            Diag.log("history: \(url.lastPathComponent) empty/corrupt — starting fresh")
        }
        return entries
    }

    /// Atomically write the current trail, with one retry (mirrors `JSONNotesStore`).
    func save(_ entries: [DictationHistoryEntry]) {
        let data = HistoryCodec.encode(entries)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) }
            catch { Diag.log("history: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
