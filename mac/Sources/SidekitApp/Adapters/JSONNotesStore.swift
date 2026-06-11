import Foundation
import SidekitCore

/// `NotesPersisting` backed by a JSON file at
/// `~/Library/Application Support/Sidekit/notes.json`.
///
/// Atomic write with a single retry (spec §9); tolerant load (missing or corrupt file → empty
/// list, logged via `Diag`). Notes never live only on disk — a save that fails twice logs and
/// keeps the caller's in-memory copy rather than crashing or clearing it.
///
/// Saves are **debounced/coalesced** (spec §4.2): rapid edits (per-keystroke from the editor)
/// only schedule the latest snapshot, written ~0.4 s later off the main thread, so typing never
/// thrashes the disk. `flush()` (on app termination) writes any pending snapshot synchronously so
/// the last edit is never lost.
///
/// `@unchecked Sendable`: mutable scheduling state (`pending`/`latest`) is guarded by `lock`; the
/// write runs on the serial `queue`. `url` is immutable.
final class JSONNotesStore: NotesPersisting, @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.speaktype.notes-save")
    private let debounce: DispatchTimeInterval = .milliseconds(400)
    private let lock = NSLock()
    private var pending: DispatchWorkItem?
    private var latest: Data?

    init() {
        self.url = AppPaths.applicationSupport.appendingPathComponent("notes.json")
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

    /// Record the latest snapshot and (re)arm the debounce timer, coalescing rapid saves.
    func save(_ notes: [Note]) {
        let data = NotesCodec.encode(notes)
        lock.lock()
        latest = data
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.writePending() }
        pending = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    /// Force the pending snapshot to disk now (synchronously) — called on app termination so the
    /// last edit survives the debounce window.
    func flush() {
        lock.lock()
        pending?.cancel()
        pending = nil
        lock.unlock()
        queue.sync { writePending() }
    }

    /// Write whatever's queued (if anything), atomically, with one retry. Runs on `queue`.
    private func writePending() {
        lock.lock()
        let data = latest
        latest = nil
        lock.unlock()
        guard let data else { return }
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
