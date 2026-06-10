import Foundation
import AppKit
import SpeakTypeCore

/// `@MainActor ObservableObject` wrapper over the pure Core `ShelfStore` — keeps Core
/// framework-free (like `NotesModel`/`HistoryModel`) while giving SwiftUI something to observe.
/// Synchronous mutators publish-then-mutate (`objectWillChange.send()` before forwarding); `ingest`
/// copies off the main actor first, then publishes + records on the main actor. Panel re-renders either way.
@MainActor
final class ShelfModel: ObservableObject {
    private let store: ShelfStore
    /// The same payload store the `ShelfStore` deletes through — held here too so drag-in can copy
    /// bytes off the main actor (see `ingest`). `nonisolated`/`Sendable`, so safe to touch off-main.
    private let payloadStore: ShelfPayloadStore

    init(store: ShelfStore, payloadStore: ShelfPayloadStore = NoopShelfPayloadStore()) {
        self.store = store
        self.payloadStore = payloadStore
        store.pruneExpired(now: Date()) // drop anything that expired while the app was closed
    }

    /// Production store backed by the JSON index file (`shelf.json`) + the filesystem payload store
    /// (one instance copies bytes in on drop and deletes them on remove / clear / expire).
    convenience init() {
        let payloads = FileSystemShelfPayloadStore()
        self.init(store: ShelfStore(persistence: JSONShelfStore(), payloads: payloads), payloadStore: payloads)
    }

    var items: [ShelfItem] { store.items }
    var isEmpty: Bool { store.items.isEmpty }
    /// Sum of every staged item's byte size — drives the footer's store-size readout.
    var totalByteSize: Int64 { store.items.reduce(0) { $0 + $1.byteSize } }

    /// The on-disk URL of an item's copied bytes (nil if the store holds none) — drives tile thumbnails.
    func fileURL(for item: ShelfItem) -> URL? { payloadStore.url(for: item) }

    /// Whether `url` is already one of our stored payloads — lets a drop ignore a tile dragged out and
    /// released back onto the shelf. `nonisolated` so the off-main drop callback can call it (the
    /// payload store is `Sendable` and the check is a pure path comparison).
    nonisolated func isStored(_ url: URL) -> Bool { payloadStore.contains(url) }

    func remove(_ id: ShelfItem.ID) { objectWillChange.send(); store.remove(id) }
    func clearAll() { objectWillChange.send(); store.clearAll() }

    /// Put the item's content on the system clipboard: the text for a snippet, the image for an image,
    /// the file URL for a file/folder (so ⌘V pastes the file itself). Builds the content *before*
    /// clearing the clipboard and no-ops on missing/unreadable bytes — so Copy never wipes the
    /// clipboard without putting something back.
    func copyToClipboard(_ item: ShelfItem) {
        guard let url = fileURL(for: item), FileManager.default.fileExists(atPath: url.path) else { return }
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let image = NSImage(contentsOf: url) else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        case .file, .folder:
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
    }

    /// Reveal the item's stored file in Finder (used for file/folder items). No-op if bytes are missing.
    func revealInFinder(_ item: ShelfItem) {
        guard let url = fileURL(for: item), FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copy every staged item's bytes into `directory`, disambiguating name collisions ("snippet.txt",
    /// "snippet 2.txt", …). Best-effort: a failed copy is logged and skipped. Returns the count written.
    @discardableResult
    func saveAll(to directory: URL) -> Int {
        var written = 0
        for item in store.items {
            guard let source = fileURL(for: item) else { continue }
            let dest = uniqueDestination(in: directory, named: shelfExportName(for: item, at: source))
            do { try FileManager.default.copyItem(at: source, to: dest); written += 1 }
            catch { Diag.log("shelf: save-all failed for \(item.displayName) (\(error))") }
        }
        return written
    }

    /// A destination URL in `directory` for `name` that doesn't clobber an existing file — inserts
    /// " 2", " 3", … before the extension until the path is free (sequential copies see each other on disk).
    private func uniqueDestination(in directory: URL, named name: String) -> URL {
        let manager = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard manager.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = directory.appendingPathComponent(next)
            n += 1
        } while manager.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Stage a dropped source (file/folder/text/image): copy its bytes via the payload store, then
    /// record the item. **`nonisolated`** so it can run inside an `NSItemProvider` load callback — a
    /// dropped file's `loadFileRepresentation` temp URL is only valid there, so the copy must happen
    /// synchronously off the main actor; only the model mutation hops back to main. A failed copy is
    /// logged and skipped, so one bad item never aborts the rest of a multi-item drop.
    nonisolated func ingest(_ source: ShelfPayloadSource) {
        do {
            let payload = try payloadStore.store(source)
            Task { @MainActor in
                objectWillChange.send()
                store.record(payload)
            }
        } catch {
            Diag.log("shelf: drop failed (\(error))")
        }
    }

    /// Expire stale items (called on app activation / periodically by the panel owner).
    func prune() { objectWillChange.send(); store.pruneExpired(now: Date()) }
}

/// The filename to export an item under: its real on-disk name for a file/folder, or the tile's label
/// + the stored extension for a text/image snippet (whose bytes live under the generic `snippet.txt` /
/// `image.png`), so several don't all land as "snippet.txt". Shared by drag-out (`ShelfTile`) and
/// Save-all (`ShelfModel.saveAll`) so the two export paths name files the same way.
func shelfExportName(for item: ShelfItem, at url: URL) -> String {
    switch item.kind {
    case .file, .folder:
        return url.lastPathComponent
    case .text, .image:
        // Sanitize: a snippet's displayName is its first line, which often holds "/" or ":" (a URL,
        // path, date, fraction). Those are path separators on disk, so an unsanitized name makes the
        // export copy land in a nonexistent subdir and fail. Fall back if it sanitizes to empty.
        let cleaned = item.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = cleaned.isEmpty ? "snippet" : cleaned
        let ext = url.pathExtension
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
