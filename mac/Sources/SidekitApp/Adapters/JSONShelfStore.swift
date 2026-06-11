import Foundation
import SidekitCore

/// `ShelfPersisting` backed by a JSON index file at
/// `~/Library/Application Support/Sidekit/shelf.json` (same support dir as `notes.json` /
/// `history.json`; all three share `AppPaths.applicationSupport`).
///
/// Stores only the item **index** (metadata); the payload bytes are a separate concern, copied by
/// the drop handler. Unlike `JSONNotesStore`, saves are **not debounced** — shelf mutations (a
/// drop, a remove, a clear, an expiry prune) are infrequent, so an immediate atomic write with one
/// retry is simplest and safe. Tolerant load (missing/corrupt → empty list, logged via `Diag`).
///
/// `@unchecked Sendable`: `url` is immutable and writes are synchronous on the caller (main actor);
/// there's no shared mutable state.
final class JSONShelfStore: ShelfPersisting, @unchecked Sendable {
    private let url: URL

    init() {
        self.url = AppPaths.applicationSupport.appendingPathComponent("shelf.json")
    }

    func load() -> [ShelfItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] } // first run
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("shelf: could not read \(url.lastPathComponent)")
            return []
        }
        let items = ShelfCodec.decode(data)
        if items.isEmpty && !data.isEmpty {
            Diag.log("shelf: \(url.lastPathComponent) empty/corrupt — starting fresh")
        }
        return items
    }

    func save(_ items: [ShelfItem]) {
        let data = ShelfCodec.encode(items)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) } // retry once
            catch { Diag.log("shelf: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
