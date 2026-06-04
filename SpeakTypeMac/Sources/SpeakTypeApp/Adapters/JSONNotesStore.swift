import Foundation
import SpeakTypeCore

/// `NotesPersisting` backed by a JSON file at
/// `~/Library/Application Support/SpeakType/notes.json`.
///
/// Atomic write with a single retry (spec §9); tolerant load (missing or corrupt file → empty
/// list, logged via `Diag`). Notes never live only on disk — a save that fails twice logs and
/// keeps the caller's in-memory copy rather than crashing or clearing it.
///
/// `@unchecked Sendable`: the single stored property is an immutable `URL`; there is no mutable
/// shared state to race (same idiom as the other adapters).
final class JSONNotesStore: NotesPersisting, @unchecked Sendable {
    private let url: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakType", isDirectory: true)
        self.url = support.appendingPathComponent("notes.json")
    }

    func load() -> [Note] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] } // first run
        guard let data = try? Data(contentsOf: url) else {
            Diag.log("notes: could not read \(url.lastPathComponent)")
            return []
        }
        let notes = NotesCodec.decode(data)
        if notes.isEmpty && !data.isEmpty {
            Diag.log("notes: \(url.lastPathComponent) empty/corrupt — starting fresh")
        }
        return notes
    }

    func save(_ notes: [Note]) {
        let data = NotesCodec.encode(notes)
        do {
            try writeAtomically(data)
        } catch {
            do { try writeAtomically(data) } // retry once (spec §9)
            catch { Diag.log("notes: save failed twice — keeping in memory (\(error))") }
        }
    }

    private func writeAtomically(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
